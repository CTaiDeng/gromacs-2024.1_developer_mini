#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2025 GaoZheng

"""
Add/normalize header version bullet for knowledge base docs.

Scope (recursive):
 - my_docs/project_docs (excluding subdir kernel_reference)
 - Skips LICENSE.md

Rules:
 - Header bullets are the lines right after the first H1 within a small window:
     - 作者 (author) bullet
     - 日期 (date, ISO YYYY-MM-DD) bullet
     - 版本 (version) bullet
 - If version is missing, insert "- 版本：v1.0.0" after the date bullet if present,
   otherwise after the author bullet, otherwise directly below H1.
 - Ensure no blank lines between author/date/version bullets.
 - Ensure exactly one blank line after the header block.

Does not modify the date value or author text.
"""

from __future__ import annotations

from pathlib import Path
import re


REPO = Path(__file__).resolve().parents[1]
KB_ROOT = REPO / "my_docs" / "project_docs"
EXCLUDE_DIR = KB_ROOT / "kernel_reference"


def process_file(md: Path) -> bool:
    try:
        text = md.read_text(encoding="utf-8")
    except Exception:
        return False
    lines = text.splitlines(True)

    # Locate first H1
    h1 = None
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("# "):
            h1 = i
            break
    if h1 is None:
        return False

    win_start = h1 + 1
    window_end = min(len(lines), h1 + 8)

    pa = re.compile(r"^\s*-\s*作者[:：]")
    pd = re.compile(r"^\s*-\s*日期[:：]\s*\d{4}-\d{2}-\d{2}\s*$")
    pv = re.compile(r"^\s*-\s*版本[:：]\s*v\d+\.\d+\.\d+\s*$", re.IGNORECASE)

    ia = id_ = iv = None
    for k in range(win_start, window_end):
        s = lines[k].strip()
        if ia is None and pa.match(s):
            ia = k
        if id_ is None and pd.match(s):
            id_ = k
        if iv is None and pv.match(s):
            iv = k

    changed = False

    # Ensure no blank between author and date
    if ia is not None and id_ is not None and id_ > ia:
        if ia + 1 < len(lines) and lines[ia + 1].strip() == "" and ia + 2 == id_:
            del lines[ia + 1]
            id_ -= 1
            if iv is not None and iv > ia:
                iv -= 1
            changed = True

    # Insert version if missing
    if iv is None:
        insert_pos = None
        if id_ is not None:
            insert_pos = id_ + 1
            if insert_pos < len(lines) and lines[insert_pos].strip() == "":
                del lines[insert_pos]
                changed = True
        elif ia is not None:
            insert_pos = ia + 1
            if insert_pos < len(lines) and lines[insert_pos].strip() == "":
                del lines[insert_pos]
                changed = True
        else:
            insert_pos = h1 + 1
            if insert_pos < len(lines) and lines[insert_pos].strip() == "":
                # keep a single blank after H1 if present
                pass
        lines.insert(insert_pos, "- 版本：v1.0.0\n")
        iv = insert_pos
        changed = True

    # Ensure no blank between date and version
    if id_ is not None and iv is not None and iv == id_ + 2:
        if lines[id_ + 1].strip() == "":
            del lines[id_ + 1]
            iv -= 1
            changed = True

    # Determine end of header block and enforce exactly one blank after it
    header_end = None
    candidates = [x for x in (ia, id_, iv) if x is not None]
    if candidates:
        header_end = max(candidates)
        if header_end + 1 < len(lines):
            if lines[header_end + 1].strip() != "":
                lines.insert(header_end + 1, "\n")
                changed = True
                header_end += 1
            while header_end + 2 < len(lines) and lines[header_end + 1].strip() == "" and lines[header_end + 2].strip() == "":
                del lines[header_end + 2]
                changed = True

    if changed:
        md.write_text("".join(lines), encoding="utf-8")
    return changed


def main() -> int:
    if not KB_ROOT.exists():
        print("[skip] my_docs/project_docs not found")
        return 0
    changed = 0
    for p in KB_ROOT.rglob("*.md"):
        if not p.is_file():
            continue
        if p.name.lower() == "license.md":
            continue
        try:
            p.relative_to(EXCLUDE_DIR)
            # inside kernel_reference -> skip
            continue
        except Exception:
            pass
        if process_file(p):
            changed += 1
            print(f"[header+version] {p}")
    print(f"[done] updated {changed} file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

