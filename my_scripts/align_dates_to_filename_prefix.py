#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.

"""
Align the in-file date line to match the 10-digit Unix timestamp prefix in
markdown files named as '<10digits>_title.md' under my_docs/project_docs (non-recursive).

Only updates the '- 日期：YYYY-MM-DD' line; does not rename files or touch subdirectories.

Defaults to dry-run. Use --apply to write changes.
"""

from __future__ import annotations

import argparse
import re
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
ROOT = REPO / "my_docs" / "project_docs"


def fmt_date(ts: int) -> str:
    return time.strftime("%Y-%m-%d", time.localtime(ts))


def align_file(md: Path, apply: bool) -> bool:
    name = md.name
    if "_" not in name:
        return False
    prefix, _ = name.split("_", 1)
    if not (len(prefix) == 10 and prefix.isdigit()):
        return False
    want = f"- 日期：{fmt_date(int(prefix))}\n"

    try:
        text = md.read_text(encoding="utf-8")
    except Exception:
        return False
    lines = text.splitlines(True)

    # Find first H1
    title_idx = None
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("# "):
            title_idx = i
            break
    if title_idx is None:
        return False

    patt_date_new = re.compile(r"^\s*-\s*日期[:：]\s*\d{4}-\d{2}-\d{2}\s*$")
    # Look within a small window after the title
    win_end = min(len(lines), title_idx + 12)
    idx_date = None
    for k in range(title_idx + 1, win_end):
        if patt_date_new.match(lines[k].strip()):
            idx_date = k
            break

    changed = False
    if idx_date is not None:
        if lines[idx_date] != want:
            if apply:
                lines[idx_date] = want
            changed = True
    else:
        # Insert after author if present, else after title
        insert_at = title_idx + 1
        if insert_at < len(lines) and lines[insert_at].strip().startswith("- 作者："):
            insert_at += 1
        if apply:
            lines.insert(insert_at, want)
        changed = True

    if changed and apply:
        md.write_text("".join(lines), encoding="utf-8")
    return changed


def main() -> int:
    ap = argparse.ArgumentParser(description="Align in-file date to filename prefix (manual, non-recursive)")
    ap.add_argument('-n', '--dry-run', action='store_true', help='Dry-run (default)')
    ap.add_argument('-a', '--apply', action='store_true', help='Apply changes to files')
    args = ap.parse_args()

    apply = bool(args.apply and not args.dry_run)

    if not ROOT.exists():
        print("project_docs not found")
        return 0
    changed = 0
    for p in sorted(ROOT.glob("*.md")):
        if align_file(p, apply=apply):
            print(f"[date-align]{' (dry-run)' if not apply else ''} updated: {p}")
            changed += 1
    mode = 'dry-run' if not apply else 'applied'
    print(f"[date-align] mode={mode} changed={changed}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
