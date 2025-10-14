#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.

"""
Align filename timestamp prefixes (10-digit Unix seconds) to the in-file date
for Markdown files under:
 - my_docs/project_docs (non-recursive)
 - my_project/gmx_split_20250924_011827/docs (non-recursive)

Rules (enforced):
 - Source of truth: in-file line '- 日期：YYYY-MM-DD'.
 - Base timestamp for a date is local midnight 'YYYY-MM-DD 00:00:00'.
 - If multiple files share the same date in the same folder, assign sequential
   seconds from the day's first second: +0, +1, +2 ... ordered by filename
   title (lexicographic ascending of the part after the underscore).
 - Does not modify file contents; only renames when needed.
"""

from __future__ import annotations

import os
import re
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

REPO = Path(__file__).resolve().parents[1]
FOLDERS = [
    REPO / "my_docs" / "project_docs",
    REPO / "my_project" / "gmx_split_20250924_011827" / "docs",
]


def read_date(md: Path) -> Optional[str]:
    try:
        text = md.read_text(encoding="utf-8")
    except Exception:
        return None
    lines = text.splitlines()
    # find first H1, then search nearby
    start = 0
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith('# '):
            start = i + 1
            break
    end = min(len(lines), start + 12)
    pat = re.compile(r"^-\s*日期[:：]\s*(\d{4}-\d{2}-\d{2})\s*$")
    for j in range(start, end):
        m = pat.match(lines[j].strip())
        if m:
            return m.group(1)
    return None


def base_epoch(ymd: str) -> int:
    st = time.strptime(ymd, "%Y-%m-%d")
    return int(time.mktime(st))


def desired_mapping(folder: Path) -> Dict[Path, int]:
    wants: Dict[Path, Tuple[str, str]] = {}
    for p in folder.glob('*.md'):
        if not p.is_file():
            continue
        name = p.name
        if '_' not in name:
            continue
        pref, rest = name.split('_', 1)
        if not (len(pref) == 10 and pref.isdigit()):
            continue
        ymd = read_date(p)
        if not ymd:
            continue
        wants[p] = (ymd, rest)

    # group by date
    groups: Dict[str, List[Path]] = {}
    for p, (ymd, _) in wants.items():
        groups.setdefault(ymd, []).append(p)

    plan: Dict[Path, int] = {}
    for ymd, lst in groups.items():
        base = base_epoch(ymd)
        if len(lst) == 1:
            plan[lst[0]] = base
        else:
            # sort by title ascending (the part after underscore)
            def title_key(path: Path) -> str:
                return path.name.split('_', 1)[1] if '_' in path.name else path.name
            for i, p in enumerate(sorted(lst, key=title_key)):
                plan[p] = base + i
    return plan


def apply(folder: Path) -> int:
    changes = 0
    plan = desired_mapping(folder)
    for p, ts in plan.items():
        try:
            pref, rest = p.name.split('_', 1)
        except ValueError:
            continue
        if pref == str(ts):
            continue
        new_name = f"{ts}_{rest}"
        new_path = p.with_name(new_name)
        # try git mv first
        try:
            os.system(f"git mv -f -- '{p.as_posix()}' '{new_path.as_posix()}' > /dev/null 2>&1")
        except Exception:
            pass
        if not new_path.exists():
            p.rename(new_path)
        print(f"[rename] {p.name} -> {new_name}")
        changes += 1
    return changes


def main() -> int:
    total = 0
    for folder in FOLDERS:
        if not folder.exists():
            continue
        total += apply(folder)
    print(f"[align-prefix-to-date v2] renamed={total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
