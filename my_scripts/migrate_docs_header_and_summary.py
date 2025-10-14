#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.

"""
Bulk-migrate my_docs/project_docs Markdown files to the new header format and
ensure a summary section exists.

New header (below first H1):
 - 作者：GaoZheng
 - 日期：YYYY-MM-DD

Rules:
- Prefer timestamp from filename prefix (10-digit) for the date.
- Convert legacy date line `日期：YYYY年MM月DD日` to new bullet list.
- Keep existing title if present; otherwise synthesize from filename sans prefix.
- Insert `## 摘要` if missing, after the date block and any immediate O3 note.
- Respect my_scripts/docs_whitelist.json excludes.

Idempotent and safe to run multiple times.
"""

from __future__ import annotations

from pathlib import Path
import re
import time
import json

REPO_ROOT = Path(__file__).resolve().parents[1]
DOCS_DIR = REPO_ROOT / "my_docs" / "project_docs"
CFG_PATH = REPO_ROOT / "my_scripts" / "docs_whitelist.json"


def _load_whitelist_config() -> tuple[list[str], list[str]]:
    wl: list[str] = []
    ex: list[str] = []
    try:
        if CFG_PATH.exists():
            data = json.loads(CFG_PATH.read_text(encoding="utf-8"))
            wl = [str(x).replace("\\", "/").rstrip("/") for x in data.get("doc_write_whitelist", [])]
            ex = [str(x).replace("\\", "/").rstrip("/") for x in data.get("doc_write_exclude", [])]
    except Exception:
        pass
    return wl, ex


def _rel_posix(p: Path) -> str:
    try:
        return p.resolve().relative_to(REPO_ROOT.resolve()).as_posix()
    except Exception:
        return p.as_posix().replace("\\", "/")


WL, EX = _load_whitelist_config()


def _is_allowed(p: Path) -> bool:
    rp = _rel_posix(p)
    for e in EX:
        if rp == e or rp.startswith(e + "/"):
            return False
    if WL:
        for w in WL:
            if rp == w or rp.startswith(w + "/"):
                return True
        return False
    return True


def fmt_date_iso(ts: int) -> str:
    return time.strftime("%Y-%m-%d", time.localtime(ts))


def ensure_header_and_summary(p: Path) -> bool:
    try:
        text = p.read_text(encoding="utf-8")
    except Exception:
        return False
    lines = text.splitlines(True)

    # Locate H1
    title_idx = None
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("# "):
            title_idx = i
            break

    # Compute title if needed
    if title_idx is None:
        stem = p.stem
        title = stem.split("_", 1)[1] if "_" in stem and stem.split("_", 1)[0].isdigit() else stem
        lines.insert(0, f"# {title}\n")
        title_idx = 0

    # Determine timestamp from filename prefix
    ts = None
    name = p.name
    if "_" in name and name.split("_", 1)[0].isdigit():
        try:
            ts = int(name.split("_", 1)[0])
        except Exception:
            ts = None
    ts = ts or int(time.time())
    author_line = "- 作者：GaoZheng\n"
    date_line = f"- 日期：{fmt_date_iso(ts)}\n"

    # Scan window below title for legacy/new header pieces
    win_start, win_end = title_idx + 1, min(len(lines), title_idx + 8)
    patt_author = re.compile(r"^\s*-\s*作者[:：]")
    patt_date_new = re.compile(r"^\s*-\s*日期[:：]\s*\d{4}-\d{2}-\d{2}\s*$")
    patt_date_old = re.compile(r"^\s*日期[:：]\s*\d{4}年\d{2}月\d{2}日\s*$")

    idx_author = None
    idx_date_new = None
    idx_date_old = None
    for k in range(win_start, win_end):
        s = lines[k].strip() if k < len(lines) else ""
        if idx_author is None and patt_author.match(s):
            idx_author = k
        if idx_date_new is None and patt_date_new.match(s):
            idx_date_new = k
        if idx_date_old is None and patt_date_old.match(s):
            idx_date_old = k

    changed = False
    # Migrate legacy date
    if idx_date_old is not None and idx_date_new is None:
        del lines[idx_date_old]
        # Insert author/date new right after title
        lines.insert(title_idx + 1, author_line)
        lines.insert(title_idx + 2, date_line)
        changed = True
        idx_author, idx_date_new = title_idx + 1, title_idx + 2
    # Ensure author
    if idx_author is None:
        lines.insert(title_idx + 1, author_line)
        changed = True
        # Adjust indices
        if idx_date_new is not None:
            idx_date_new += 1
    else:
        if lines[idx_author] != author_line:
            lines[idx_author] = author_line
            changed = True
    # Ensure date new
    if idx_date_new is None:
        insert_after = (idx_author if idx_author is not None else title_idx) + 1
        lines.insert(insert_after, date_line)
        changed = True
        idx_date_new = insert_after
    else:
        if lines[idx_date_new] != date_line:
            lines[idx_date_new] = date_line
            changed = True

    # Ensure blank line after header block
    end_hdr = max(idx for idx in (idx_author, idx_date_new) if idx is not None)
    if end_hdr + 1 < len(lines) and lines[end_hdr + 1].strip() != "":
        lines.insert(end_hdr + 1, "\n")
        changed = True

    # Ensure 摘要 section
    has_summary = False
    patt_summary_h = re.compile(r"^\s*#{2,4}\s*摘要\s*$")
    patt_summary_inline = re.compile(r"^摘要[:：]", re.I)
    for ln in lines:
        if patt_summary_h.match(ln.strip()) or patt_summary_inline.match(ln.strip()):
            has_summary = True
            break
    if not has_summary:
        # Build a simple summary from first paragraph after header blocks
        insert_pos = end_hdr + 1
        # Skip over an immediate O3 note if present
        if insert_pos < len(lines) and lines[insert_pos].lstrip().startswith("#### ***"):
            insert_pos += 1
            if insert_pos < len(lines) and lines[insert_pos].strip() == "":
                insert_pos += 1
        # Capture first paragraph as summary text
        k = insert_pos
        # Skip empty lines
        while k < len(lines) and lines[k].strip() == "":
            k += 1
        buf: list[str] = []
        while k < len(lines) and lines[k].strip() and not lines[k].lstrip().startswith("#"):
            buf.append(lines[k].strip())
            k += 1
        raw = " ".join(buf)
        raw = re.sub(r"\s+", " ", raw)
        summary = raw[:219] + ("…" if len(raw) > 219 else "") if raw else "(自动补齐的摘要占位)"
        block = ["## 摘要\n", summary + "\n", "\n"]
        lines[insert_pos:insert_pos] = block
        changed = True

    if changed:
        p.write_text("".join(lines), encoding="utf-8")
    return changed


def main() -> int:
    changed = []
    if not DOCS_DIR.exists():
        print("project_docs missing; nothing to migrate")
        return 0
    for p in sorted(DOCS_DIR.glob("*.md")):
        if not _is_allowed(p):
            continue
        if ensure_header_and_summary(p):
            changed.append(_rel_posix(p))
    print(f"Migrated {len(changed)} file(s)")
    for f in changed:
        print(" -", f)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
