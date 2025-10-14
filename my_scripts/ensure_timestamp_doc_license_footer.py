#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.

"""
Append a canonical CC BY-NC-ND 4.0 footer to Markdown docs named as
  `^\d{10}_.+\.md$`
under specified roots:
  - my_docs/project_docs (excluding kernel_reference)
  - my_project/gmx_split_20250924_011827/docs
Also copy my_docs/LICENSE.md to my_project/gmx_split_20250924_011827/docs.

Idempotent: will not append if a footer marker already exists.
"""

from __future__ import annotations

import re
import shutil
import subprocess
import time
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
CFG_PATH = ROOT / "my_scripts" / "docs_whitelist.json"

PATTERN = re.compile(r"^\d{10}_.+\.md$")
MARKER = "许可声明 (License)"
LINK_SNIPPET = "creativecommons.org/licenses/by-nc-nd/4.0"


def iter_target_files() -> list[Path]:
    targets: list[Path] = []
    # 0) repo-root docs (non-recursive)
    root_docs = ROOT / "docs"
    if root_docs.exists():
        for p in root_docs.glob("*.md"):
            if p.is_file() and PATTERN.match(p.name):
                targets.append(p)
    # 1) my_docs/project_docs (exclude kernel_reference)
    proj = ROOT / "my_docs" / "project_docs"
    if proj.exists():
        for p in proj.rglob("*.md"):
            if not p.is_file():
                continue
            try:
                rel = p.resolve().relative_to(ROOT.resolve()).as_posix()
            except Exception:
                rel = p.as_posix().replace("\\", "/")
            if rel.startswith("my_docs/project_docs/kernel_reference/"):
                continue
            if PATTERN.match(p.name):
                targets.append(p)
    # 2) my_project/gmx_split_20250924_011827/docs
    proj_docs = ROOT / "my_project" / "gmx_split_20250924_011827" / "docs"
    if proj_docs.exists():
        for p in proj_docs.rglob("*.md"):
            if not p.is_file():
                continue
            if PATTERN.match(p.name):
                targets.append(p)
    return targets


def read_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except Exception:
        return path.read_text(errors="ignore")


def write_text(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")


def _run_git(args: list[str]) -> str:
    try:
        out = subprocess.check_output(["git", *args], cwd=ROOT)
        try:
            return out.decode("utf-8", errors="ignore")
        except Exception:
            return out.decode(errors="ignore")
    except Exception:
        return ""


def _creation_year(path: Path) -> int:
    # Prefer 10-digit prefix in filename
    name = path.name
    try:
        pref = name.split("_", 1)[0]
        if len(pref) == 10 and pref.isdigit():
            ts = int(pref)
            return time.localtime(ts).tm_year
    except Exception:
        pass
    # Fallback to first add commit year
    out = _run_git(["log", "--follow", "--diff-filter=A", "--format=%at", "--", str(path)])
    ts = out.strip().splitlines()[-1] if out.strip() else ""
    if ts.isdigit():
        return time.localtime(int(ts)).tm_year
    # Fallback to file mtime
    try:
        return time.localtime(path.stat().st_mtime).tm_year
    except Exception:
        return time.localtime().tm_year


def _last_mod_year(path: Path) -> int:
    # Prefer last commit year
    out = _run_git(["log", "-1", "--format=%at", "--", str(path)])
    ts = out.strip().splitlines()[-1] if out.strip() else ""
    if ts.isdigit():
        return time.localtime(int(ts)).tm_year
    try:
        return time.localtime(path.stat().st_mtime).tm_year
    except Exception:
        return time.localtime().tm_year


def _year_label(path: Path) -> str:
    c = _creation_year(path)
    m = _last_mod_year(path)
    if m > c:
        return f"{c}-{m}"
    return str(c)


def ensure_footer(path: Path) -> bool:
    """Ensure footer exists with exact spacing and dynamic year label.
    Returns True if file modified.
    """
    text = read_text(path)
    year_label = _year_label(path)
    canonical = (
        "\n\n---\n\n"
        "**许可声明 (License)**\n\n"
        f"Copyright (C) {year_label} GaoZheng\n\n"
        "本文档采用[知识共享-署名-非商业性使用-禁止演绎 4.0 国际许可协议 (CC BY-NC-ND 4.0)](https://creativecommons.org/licenses/by-nc-nd/4.0/deed.zh-Hans)进行许可。\n"
    )

    # If marker exists, normalize by replacing from the marker to end
    idx = text.rfind(MARKER)
    if idx != -1:
        # Start from the beginning of the line containing the marker
        line_start = text.rfind("\n", 0, idx)
        line_start = 0 if line_start == -1 else line_start + 1
        pre = text[:line_start]
        # Trim trailing whitespace and an optional preceding '---' separator with surrounding blank lines
        pre_lines = pre.splitlines()
        # Clean any trailing blank lines / stray '**' / '---' in order, repeatedly
        changed = True
        while changed and pre_lines:
            changed = False
            while pre_lines and pre_lines[-1].strip() == "":
                pre_lines.pop(); changed = True
            if pre_lines and pre_lines[-1].strip() == "**":
                pre_lines.pop(); changed = True
            while pre_lines and pre_lines[-1].strip() == "":
                pre_lines.pop(); changed = True
            if pre_lines and pre_lines[-1].strip() == "---":
                pre_lines.pop(); changed = True
            while pre_lines and pre_lines[-1].strip() == "":
                pre_lines.pop(); changed = True
        head = ("\n".join(pre_lines)).rstrip("\r\n")
        new_text = head + canonical
        if new_text != text:
            write_text(path, new_text)
            return True
        return False
    # Else append canonical footer
    base = text.rstrip("\r\n")
    new_text = base + canonical
    if new_text != text:
        write_text(path, new_text)
        return True
    return False


def copy_license_into_project() -> bool:
    src = ROOT / "my_docs" / "project_docs" / "LICENSE.md"
    dst_dir = ROOT / "my_project" / "gmx_split_20250924_011827" / "docs"
    dst = dst_dir / "LICENSE.md"
    if not src.exists() or not dst_dir.exists():
        return False
    # Respect doc_write_exclude
    excluded = set()
    try:
        if CFG_PATH.exists():
            data = json.loads(CFG_PATH.read_text(encoding="utf-8"))
            for e in data.get("doc_write_exclude", []):
                excluded.add(str(e).replace("\\", "/").rstrip("/"))
    except Exception:
        pass
    try:
        rel_dst = dst.resolve().relative_to(ROOT.resolve()).as_posix()
    except Exception:
        rel_dst = dst.as_posix().replace("\\", "/")
    if rel_dst in excluded or any(rel_dst.startswith(e + "/") for e in excluded):
        # Do not modify excluded paths
        return False
    try:
        s = read_text(src)
        d = read_text(dst) if dst.exists() else None
        if d == s:
            return False
    except Exception:
        pass
    shutil.copyfile(src, dst)
    return True


def main() -> int:
    modified = 0
    for p in iter_target_files():
        if ensure_footer(p):
            print(f"[footer] appended: {p}")
            modified += 1
    if copy_license_into_project():
        print("[footer] copied LICENSE.md into project docs")
    print(f"[footer] done. modified={modified}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
