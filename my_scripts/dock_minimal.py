#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.

"""
Minimal prototype: candidate generation -> mdrun -rerun -> energy extract -> ranking

Prerequisites:
  - GROMACS installed and `gmx` in PATH
  - TPR with energygrps = Protein Ligand
  - start.gro consistent with TPR atom order (contains Protein + Ligand)
  - index.ndx with groups [ Protein ] and [ Ligand ]

Usage example:
  python dock_minimal.py \
    --tpr topol.tpr --structure start.gro --ndx index.ndx \
    --n-poses 50 --trans 0.5 --rot 20 --workdir out --nt 1 --jobs 2

Scoring:
  score = (Coul-SR:Protein-Ligand) + (LJ-SR:Protein-Ligand), lower is better.
"""

from __future__ import annotations

import argparse
import math
import os
import random
import re
import shutil
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple, Dict, Optional


# -------------------------
# I/O helpers: .gro & .ndx
# -------------------------


@dataclass
class AtomRecord:
    resid: int
    resname: str
    atomname: str
    atomnr: int
    x: float
    y: float
    z: float


@dataclass
class GroStructure:
    title: str
    atoms: List[AtomRecord]
    box: Tuple[float, float, float]


def read_gro(path: Path) -> GroStructure:
    with open(path, "r", encoding="utf-8") as f:
        lines = [ln.rstrip("\n") for ln in f]
    if len(lines) < 3:
        raise ValueError("GRO file too short")
    title = lines[0]
    try:
        natoms = int(lines[1].strip())
    except Exception as e:
        raise ValueError(f"Invalid atom count line: {lines[1]}") from e
    atom_lines = lines[2 : 2 + natoms]
    if len(atom_lines) != natoms:
        raise ValueError("GRO file atom count mismatch")
    atoms: List[AtomRecord] = []
    for ln in atom_lines:
        # GRO fixed-width format (classic):
        #  0-4 resid, 5-9 resname, 10-14 atomname, 15-19 atomnr, 20-27 x, 28-35 y, 36-43 z
        # Allow for slight deviations: fallback to whitespace split for coords.
        try:
            resid = int(ln[0:5])
            resname = ln[5:10].strip()
            atomname = ln[10:15].strip()
            atomnr = int(ln[15:20])
            # positions in nm
            x = float(ln[20:28])
            y = float(ln[28:36])
            z = float(ln[36:44])
        except Exception:
            parts = ln.split()
            if len(parts) < 6:
                raise ValueError(f"Malformed GRO atom line: {ln}")
            # When split, we may lose names spacing; keep names best-effort.
            resid = int(parts[0])
            resname = parts[1]
            atomname = parts[2]
            atomnr = int(parts[3])
            x, y, z = map(float, parts[4:7])
        atoms.append(AtomRecord(resid, resname, atomname, atomnr, x, y, z))
    # box line
    try:
        box_parts = lines[2 + natoms].split()
        if len(box_parts) < 3:
            raise ValueError
        box = (float(box_parts[0]), float(box_parts[1]), float(box_parts[2]))
    except Exception as e:
        raise ValueError(f"Invalid GRO box line: {lines[2 + natoms]}") from e
    return GroStructure(title, atoms, box)


def write_gro(struct: GroStructure, path: Path):
    with open(path, "w", encoding="utf-8") as f:
        f.write(struct.title + "\n")
        f.write(f"{len(struct.atoms):5d}\n")
        for a in struct.atoms:
            # Classic formatting widths, positions nm with 3 decimals
            f.write(
                f"{a.resid:5d}{a.resname:>5s}{a.atomname:>5s}{a.atomnr:5d}" \
                f"{a.x:8.3f}{a.y:8.3f}{a.z:8.3f}\n"
            )
        f.write(f"{struct.box[0]:10.5f} {struct.box[1]:10.5f} {struct.box[2]:10.5f}\n")


def parse_ndx_groups(path: Path) -> Dict[str, List[int]]:
    groups: Dict[str, List[int]] = {}
    current: Optional[str] = None
    with open(path, "r", encoding="utf-8") as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            if ln.startswith("[") and ln.endswith("]"):
                name = ln[1:-1].strip()
                current = name
                groups[current] = []
                continue
            if current is None:
                continue
            # numbers separated by spaces
            for tok in ln.split():
                try:
                    idx = int(tok)
                except ValueError:
                    continue
                groups[current].append(idx)
    return groups


# -------------------------
# Geometry helpers
# -------------------------


def random_rotation_matrix(max_deg: float) -> List[List[float]]:
    # Random axis, angle in [-max_deg, max_deg]
    if max_deg <= 0:
        return [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
    theta = math.radians(random.uniform(-max_deg, max_deg))
    # random unit axis
    while True:
        x, y, z = random.uniform(-1, 1), random.uniform(-1, 1), random.uniform(-1, 1)
        n = math.sqrt(x * x + y * y + z * z)
        if n > 1e-6:
            x, y, z = x / n, y / n, z / n
            break
    c, s, C = math.cos(theta), math.sin(theta), 1 - math.cos(theta)
    return [
        [x * x * C + c, x * y * C - z * s, x * z * C + y * s],
        [y * x * C + z * s, y * y * C + c, y * z * C - x * s],
        [z * x * C - y * s, z * y * C + x * s, z * z * C + c],
    ]


def apply_rigid_transform(
    struct: GroStructure, ligand_atom_indices_1based: List[int], trans_nm: float, rot_deg: float
) -> GroStructure:
    # Convert to 0-based
    lig_idx0 = [i - 1 for i in ligand_atom_indices_1based]
    atoms = list(struct.atoms)  # shallow copy
    # ligand centroid
    xs = [atoms[i].x for i in lig_idx0]
    ys = [atoms[i].y for i in lig_idx0]
    zs = [atoms[i].z for i in lig_idx0]
    cx, cy, cz = sum(xs) / len(xs), sum(ys) / len(ys), sum(zs) / len(zs)
    # translation
    tx = random.uniform(-trans_nm, trans_nm)
    ty = random.uniform(-trans_nm, trans_nm)
    tz = random.uniform(-trans_nm, trans_nm)
    R = random_rotation_matrix(rot_deg)
    # transform ligand atoms
    for i in lig_idx0:
        a = atoms[i]
        rx, ry, rz = a.x - cx, a.y - cy, a.z - cz
        nx = R[0][0] * rx + R[0][1] * ry + R[0][2] * rz + cx + tx
        ny = R[1][0] * rx + R[1][1] * ry + R[1][2] * rz + cy + ty
        nz = R[2][0] * rx + R[2][1] * ry + R[2][2] * rz + cz + tz
        atoms[i] = AtomRecord(a.resid, a.resname, a.atomname, a.atomnr, nx, ny, nz)
    return GroStructure(struct.title, atoms, struct.box)


# -------------------------
# GROMACS wrappers
# -------------------------


def run_cmd(cmd: List[str], cwd: Path, input_text: Optional[str] = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd,
        cwd=str(cwd),
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def mdrun_rerun(gmx: str, tpr: Path, structure: Path, deffnm: str, cwd: Path, nt: int = 1) -> None:
    cmd = [gmx, "mdrun", "-s", str(tpr), "-rerun", str(structure), "-deffnm", deffnm, "-nt", str(nt), "-nb", "cpu"]
    p = run_cmd(cmd, cwd)
    if p.returncode != 0:
        raise RuntimeError(f"mdrun -rerun failed: {p.stderr}\nCMD: {' '.join(cmd)}")


def list_energy_terms(gmx: str, edr: Path, cwd: Path) -> Dict[str, int]:
    # Trigger listing and exit immediately by sending '0\n'
    p = run_cmd([gmx, "energy", "-f", str(edr), "-xvg", "none"], cwd=cwd, input_text="0\n")
    if p.returncode != 0:
        raise RuntimeError(f"gmx energy listing failed: {p.stderr}")
    # Parse lines like: "  34  Coul-SR:Protein-Ligand"
    mapping: Dict[str, int] = {}
    for ln in p.stdout.splitlines():
        m = re.match(r"^\s*(\d+)\s+(.+)$", ln.strip())
        if m:
            idx = int(m.group(1))
            name = m.group(2).strip()
            mapping[name] = idx
    return mapping


def extract_energy_sum(
    gmx: str,
    edr: Path,
    cwd: Path,
    term_names: Tuple[str, str] = ("Coul-SR:Protein-Ligand", "LJ-SR:Protein-Ligand"),
) -> float:
    mapping = list_energy_terms(gmx, edr, cwd)
    missing = [t for t in term_names if t not in mapping]
    if missing:
        raise RuntimeError(
            f"Energy terms not found in {edr.name}: {missing}. Ensure energygrps=Protein Ligand in TPR."
        )
    sel = f"{mapping[term_names[0]]} {mapping[term_names[1]]} 0\n"
    out_xvg = edr.with_suffix("").name + "_terms.xvg"
    p = run_cmd([gmx, "energy", "-f", str(edr), "-xvg", "none", "-o", out_xvg], cwd=cwd, input_text=sel)
    if p.returncode != 0:
        raise RuntimeError(f"gmx energy extract failed: {p.stderr}")
    # Parse data lines from xvg (time col + two energy cols); take the last frame.
    data_path = cwd / out_xvg
    last_vals: Optional[Tuple[float, float, float]] = None
    with open(data_path, "r", encoding="utf-8") as f:
        for ln in f:
            ln = ln.strip()
            if not ln or ln.startswith("#") or ln.startswith("@"):  # skip comments
                continue
            parts = ln.split()
            if len(parts) >= 3:
                try:
                    t, v1, v2 = float(parts[0]), float(parts[1]), float(parts[2])
                    last_vals = (t, v1, v2)
                except ValueError:
                    pass
    if last_vals is None:
        raise RuntimeError(f"No data parsed from {out_xvg}")
    _, v1, v2 = last_vals
    return v1 + v2


# -------------------------
# Main workflow
# -------------------------


def run_pose(
    i: int,
    base_struct: GroStructure,
    lig_indices: List[int],
    gmx: str,
    tpr: Path,
    workdir: Path,
    trans: float,
    rot: float,
    nt: int,
) -> Tuple[int, float, Path]:
    pose_dir = workdir
    cand_path = pose_dir / f"candidate_{i:04d}.gro"
    deffnm = f"pose_{i:04d}"
    # Generate candidate
    cand_struct = apply_rigid_transform(base_struct, lig_indices, trans, rot)
    write_gro(cand_struct, cand_path)
    # Rerun
    mdrun_rerun(gmx, tpr, cand_path, deffnm, pose_dir, nt=nt)
    edr = pose_dir / f"{deffnm}.edr"
    score = extract_energy_sum(gmx, edr, pose_dir)
    return i, score, cand_path


def main():
    ap = argparse.ArgumentParser(description="Minimal docking-by-rerun prototype")
    ap.add_argument("--gmx", default=os.environ.get("GMX", "gmx"), help="gmx executable")
    ap.add_argument("--tpr", required=True, type=Path)
    ap.add_argument("--structure", required=True, type=Path)
    ap.add_argument("--ndx", required=True, type=Path)
    ap.add_argument("--workdir", required=True, type=Path)
    ap.add_argument("--n-poses", type=int, default=20)
    ap.add_argument("--trans", type=float, default=0.5, help="max translation (nm)")
    ap.add_argument("--rot", type=float, default=20.0, help="max rotation (deg)")
    ap.add_argument("--jobs", type=int, default=1, help="parallel workers")
    ap.add_argument("--nt", type=int, default=1, help="threads per mdrun")
    ap.add_argument("--seed", type=int, default=None)
    args = ap.parse_args()

    if args.seed is not None:
        random.seed(args.seed)

    args.workdir.mkdir(parents=True, exist_ok=True)

    # Basic checks
    for p in [args.tpr, args.structure, args.ndx]:
        if not p.exists():
            sys.exit(f"Input not found: {p}")
    if shutil.which(args.gmx) is None:
        sys.exit(f"Cannot find gmx executable: {args.gmx}")

    # Load structure & ligand indices
    base_struct = read_gro(args.structure)
    groups = parse_ndx_groups(args.ndx)
    if "Ligand" not in groups:
        sys.exit("index.ndx must contain a group named 'Ligand'")
    lig_indices = groups["Ligand"]
    if not lig_indices:
        sys.exit("'Ligand' group is empty in index.ndx")

    # Run candidates
    results: List[Tuple[int, float, Path]] = []
    if args.jobs <= 1:
        for i in range(args.n_poses):
            try:
                results.append(
                    run_pose(i, base_struct, lig_indices, args.gmx, args.tpr, args.workdir, args.trans, args.rot, args.nt)
                )
            except Exception as e:
                print(f"[WARN] Pose {i} failed: {e}", file=sys.stderr)
    else:
        with ThreadPoolExecutor(max_workers=args.jobs) as ex:
            futs = [
                ex.submit(
                    run_pose,
                    i,
                    base_struct,
                    lig_indices,
                    args.gmx,
                    args.tpr,
                    args.workdir,
                    args.trans,
                    args.rot,
                    args.nt,
                )
                for i in range(args.n_poses)
            ]
            for fut in as_completed(futs):
                try:
                    results.append(fut.result())
                except Exception as e:
                    print(f"[WARN] Pose failed: {e}", file=sys.stderr)

    # Sort and save summary
    results.sort(key=lambda t: t[1])  # lower energy is better
    out_csv = args.workdir / "scores.csv"
    with open(out_csv, "w", encoding="utf-8") as f:
        f.write("pose,score_kJ_per_mol,candidate_gro\n")
        for i, score, path in results:
            f.write(f"{i},{score},{path.name}\n")

    # Print top-10 summary
    print("Top poses (lowest score):")
    for i, (pid, score, path) in enumerate(results[:10]):
        print(f"{i+1:2d}. pose={pid:04d}  score={score: .3f}  file={path.name}")
    print(f"\nAll scores written to: {out_csv}")


if __name__ == "__main__":
    main()
