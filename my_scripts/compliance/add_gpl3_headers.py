#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.

"""
Add GPL-3.0 headers to source files, mirroring add_gpl3_headers.ps1 behavior.
Only applies to code files (not Markdown), under default paths:
  src, api, include, admin, scripts, tests, python_packaging
Excludes docs and generated/vendor trees; respects hard-coded never-touch list.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path
import subprocess
from typing import Iterable, Sequence

def get_repo_root() -> Path:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            check=True,
        )
        p = out.stdout.strip()
        if p:
            return Path(p)
    except Exception:
        pass
    # Fallback: this script resides under my_scripts/compliance
    return Path(__file__).resolve().parents[2]

REPO_ROOT = get_repo_root()

DEFAULT_PATHS = [
    REPO_ROOT / "src",
    REPO_ROOT / "api",
    REPO_ROOT / "include",
    REPO_ROOT / "admin",
    REPO_ROOT / "scripts",
    REPO_ROOT / "tests",
    REPO_ROOT / "python_packaging",
    REPO_ROOT / "my_scripts",
]

EXTENSIONS = {
    ".c",
    ".cc",
    ".cpp",
    ".cxx",
    ".h",
    ".hh",
    ".hpp",
    ".hxx",
    ".cu",
    ".cuh",
    ".py",
    ".sh",
    ".ps1",
    ".psm1",
    ".cmake",
    ".bat",
    ".cmd",
    ".js",
    ".ts",
    ".java",
    ".rs",
    ".go",
    ".m",
    ".mm",
    ".R",
}

EXCLUDE_PREFIXES = {
    ".git",
    ".venv",
    ".pip-cache",
    "cmake-build-release-visual-studio-2022",
    "out",
    "logs",
    "my_docs",
    "res",
    "share",
}

NEVER_TOUCH = {
    "my_docs/project_docs/LICENSE.md",
    "my_project/gmx_split_20250924_011827/docs/LICENSE.md",
}


def rel(p: Path) -> str:
    try:
        return p.resolve().relative_to(REPO_ROOT.resolve()).as_posix()
    except Exception:
        return p.as_posix().replace("\\", "/")


def should_exclude(p: Path) -> bool:
    rp = rel(p)
    for nt in NEVER_TOUCH:
        if rp == nt:
            return True
    parts = rp.split("/")
    if parts:
        if parts[0] in EXCLUDE_PREFIXES:
            return True
        # kernel_reference or acpype subtrees
        if rp.startswith("my_docs/project_docs/kernel_reference/"):
            return True
        if "/LIG.acpype/" in ("/" + rp + "/"):
            return True
    return False


def detect_style(path: Path) -> str:
    name = path.name
    ext = path.suffix.lower()
    if name == "CMakeLists.txt":
        return "hash"
    if ext in {
        ".c",
        ".cc",
        ".cpp",
        ".cxx",
        ".h",
        ".hh",
        ".hpp",
        ".hxx",
        ".cu",
        ".cuh",
        ".java",
        ".js",
        ".ts",
        ".m",
        ".mm",
    }:
        return "block"
    if ext in {".bat", ".cmd"}:
        return "bat"
    return "hash"


def already_has_header(lines: list[str]) -> bool:
    head = "".join(lines[:200])
    return bool(
        re.search(r"SPDX-License-Identifier:\s*GPL-3\.0", head, re.I)
        and re.search(r"GNU\s+General\s+Public\s+License", head, re.I)
    )


def has_gromacs_lgpl_header(lines: list[str]) -> bool:
    head = "".join(lines[:800])
    return (
        ("GROMACS molecular simulation package" in head)
        and ("Lesser General Public License" in head or "LGPL" in head)
    )


def make_header_lines(style: str, spdx: str = "GPL-3.0-only") -> list[str]:
    year = "2025"
    copy = f"Copyright (C) {year} GaoZheng"
    gpl_lines = [
        copy,
        f"SPDX-License-Identifier: {spdx}",
        "This file is part of this project.",
        "Licensed under the GNU General Public License version 3.",
        "See https://www.gnu.org/licenses/gpl-3.0.html for details.",
    ]
    if style == "block":
        body = ["/*"] + [f" * {l}" for l in gpl_lines] + [" */"]
    elif style == "bat":
        body = [f"REM {l}" for l in gpl_lines]
    else:
        body = [f"# {l}" for l in gpl_lines]
    return body


def make_consolidated_header(style: str, gmx_year: str = "2010-", spdx: str = "GPL-3.0-only") -> list[str]:
    core = [
        f"SPDX-License-Identifier: {spdx}",
        "",
        f"Copyright (C) {gmx_year} The GROMACS Authors",
        "Copyright (C) 2025 GaoZheng",
        "",
        "This program is free software: you can redistribute it and/or modify",
        "it under the terms of the GNU General Public License as published by",
        "the Free Software Foundation, version 3.",
        "",
        "This program is distributed in the hope that it will be useful,",
        "but WITHOUT ANY WARRANTY; without even the implied warranty of",
        "MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the",
        "GNU General Public License for more details.",
        "",
        "You should have received a copy of the GNU General Public License",
        "along with this program. If not, see <https://www.gnu.org/licenses/>.",
        "",
        "---",
        "",
        "This file is part of a modified version of the GROMACS molecular simulation package.",
        "For details on the original project, consult https://www.gromacs.org.",
        "",
        "To help fund GROMACS development, we humbly ask that you cite",
        "the research papers on the package. Check out https://www.gromacs.org.",
    ]
    if style == "block":
        return ["/*"] + [f" * {l}" if l else " *" for l in core] + [" */"]
    if style == "bat":
        return [f"REM {l}" if l else "REM" for l in core]
    return [f"# {l}" if l else "#" for l in core]


def insert_header(path: Path, spdx: str = "GPL-3.0-only") -> bool:
    try:
        text = path.read_text(encoding="utf-8")
    except Exception:
        try:
            text = path.read_text(errors="ignore")
        except Exception:
            return False
    lines = text.splitlines()
    style = detect_style(path)

    # Normalize GaoZheng year format even if header already present (2025- -> 2025)
    head_text = "\n".join(lines[:300])
    if "Copyright (C) 2025 GaoZheng" in head_text:
        new_text = text.replace("Copyright (C) 2025 GaoZheng", "Copyright (C) 2025 GaoZheng")
        if new_text != text:
            path.write_text(new_text, encoding="utf-8")
            return True

    # Consolidate if both headers are present
    if has_gromacs_lgpl_header(lines) and re.search(r"SPDX-License-Identifier:\s*GPL-3\.0", "".join(lines[:300]), re.I):
        # Extract GROMACS year prefix if available
        head_text = "\n".join(lines[:400])
        m = re.search(r"Copyright\s+(\d{4}-?)\s*The\s+GROMACS\s+Authors", head_text)
        gmx_year = m.group(1) if m else "2010-"
        cons = make_consolidated_header(style, gmx_year=gmx_year, spdx=spdx)
        # Preserve shebang/encoding
        insert_at = 0
        if lines and lines[0].startswith("#!"):
            insert_at = 1
        if len(lines) > insert_at and ("coding" in lines[insert_at].lower() and "utf-8" in lines[insert_at].lower()):
            insert_at += 1
        # Skip up to two top comment blocks or comment-lines
        i = insert_at
        if style == "block":
            removed = 0
            while i < len(lines) and removed < 2:
                if lines[i].lstrip().startswith("/*"):
                    j = i
                    while j < len(lines) and not lines[j].rstrip().endswith("*/"):
                        j += 1
                    i = j + 1
                    removed += 1
                elif not lines[i].strip():
                    i += 1
                else:
                    break
        else:
            while i < len(lines) and (not lines[i].strip() or lines[i].lstrip().startswith(('#','REM','rem'))):
                i += 1
        new_lines: list[str] = []
        if insert_at:
            new_lines.extend(lines[:insert_at])
        new_lines.extend(cons)
        if i < len(lines) and lines[i].strip():
            new_lines.append("")
        new_lines.extend(lines[i:])
        out = "\n".join(new_lines)
        if not out.endswith("\n"):
            out += "\n"
        path.write_text(out, encoding="utf-8")
        return True

    # If already consolidated (SPDX + modified GROMACS hint), skip
    if already_has_header(lines) and "modified version of the GROMACS" in "\n".join(lines[:200]):
        return False

    if already_has_header(lines):
        return False
    header = make_header_lines(style, spdx)
    insert_at = 0
    if lines and lines[0].startswith("#!"):
        insert_at = 1
    if len(lines) > insert_at and ("coding" in lines[insert_at] and "utf-8" in lines[insert_at].lower()):
        insert_at += 1
    new_lines = []
    if insert_at:
        new_lines.extend(lines[:insert_at])
    new_lines.extend(header)
    new_lines.extend(lines[insert_at:])
    out = "\n".join(new_lines)
    if not out.endswith("\n"):
        out += "\n"
    path.write_text(out, encoding="utf-8")
    return True


def iter_files(paths: Iterable[Path]) -> Iterable[Path]:
    for base in paths:
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if not p.is_file():
                continue
            if should_exclude(p):
                continue
            if p.suffix not in EXTENSIONS and p.name != "CMakeLists.txt":
                continue
            yield p


def main(argv: Sequence[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Add or consolidate GPL-3.0 headers in source files")
    ap.add_argument("paths", nargs="*", help="Files or directories to process (defaults to code dirs)")
    args = ap.parse_args(argv)

    scanned = 0
    updated = 0
    skipped = 0
    if args.paths:
        files: list[Path] = []
        dirs: list[Path] = []
        for p in args.paths:
            pp = Path(p)
            if not pp.is_absolute():
                pp = (Path.cwd() / pp).resolve()
            if pp.is_file():
                files.append(pp)
            else:
                dirs.append(pp)
        it = list(files) + list(iter_files(dirs))
    else:
        it = iter_files(DEFAULT_PATHS)

    for f in it:
        scanned += 1
        try:
            if insert_header(f):
                updated += 1
            else:
                skipped += 1
        except Exception:
            skipped += 1
    print(f"[gpl-headers-py] scanned={scanned} updated={updated} skipped={skipped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
