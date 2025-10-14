#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.

"""
Align my_docs knowledge-base files and keep docs consistent:
1) For files named as `<digits>_...`, rename so `<digits>` equals first Git add
   timestamp (Unix seconds), preserving history via `git mv`. For `my_docs/project_docs`,
   additionally enforce the `<digits>` prefix to be unique across the directory (treat it
   as a document ID): when collisions occur (e.g. same-second adds), step back by 1 second
   repeatedly until a unique prefix is obtained.
2) For Markdown files, insert/normalize the date line `日期：YYYY年MM月DD日`
   right below the first H1 title, derived from the timestamp used in step 1.
3) When the content contains any O3-related keywords, insert a canonical O3 note
   line right below the date line (idempotent and de-duplicated).

Special-case exemption:
- For `my_docs/project_docs` with filename timestamp prefixes in
  {1752417159..1752417168}, do NOT rename; use their filename timestamp directly
  for the date line.

Safe to run repeatedly (idempotent).
"""

from __future__ import annotations

import re
import subprocess
import time
from pathlib import Path
import json
import os


ROOTS = [Path("my_docs"), Path("my_project")]

# Config: doc write whitelist/exclude
REPO_ROOT = Path(__file__).resolve().parents[1]
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


WL, EX = _load_whitelist_config()


def _rel_posix(p: Path) -> str:
    try:
        return p.resolve().relative_to(REPO_ROOT.resolve()).as_posix()
    except Exception:
        return p.as_posix().replace("\\", "/")


def _is_allowed(p: Path) -> bool:
    rp = _rel_posix(p)
    # Exclude takes precedence
    for e in EX:
        if rp == e or rp.startswith(e + "/"):
            return False
    # If whitelist provided, require match; else allow
    if WL:
        for w in WL:
            if rp == w or rp.startswith(w + "/"):
                return True
        return False
    return True

# Trigger keywords for adding O3-related reference note
O3_KEYWORDS = [
    "O3理论",
    "O3元数学理论",
    "主纤维丛版广义非交换李代数",
    "PFB-GNLA",
]

O3_NOTE = (
    "#### ***注：“O3理论/O3元数学理论/主纤维丛版广义非交换李代数(PFB-GNLA)”相关理论参见： [作者（GaoZheng）网盘分享](https://drive.google.com/drive/folders/1lrgVtvhEq8cNal0Aa0AjeCNQaRA8WERu?usp=sharing) 或 [作者（GaoZheng）开源项目](https://github.com/CTaiDeng/open_meta_mathematical_theory) 或 [作者（GaoZheng）主页](https://mymetamathematics.blogspot.com)，欢迎访问！***\n"
)

# Exempt these filename timestamp prefixes under my_docs/project_docs
EXEMPT_PREFIXES = {
    1759156359, 1759156360, 1759156361, 1759156362, 1759156363,
    1759156364, 1759156365, 1759156366, 1759156367, 1759156368,
}

# --- New: enforce unique prefix (as document ID) within my_docs/project_docs ---
PROJ_DOCS_DIR = Path("my_docs/project_docs")

def _scan_project_docs_prefixes() -> dict[int, set[Path]]:
    """Return mapping: ts_prefix -> set(paths) for my_docs/project_docs (excludes kernel_reference
    via whitelist/exclude rules in callers).
    """
    mapping: dict[int, set[Path]] = {}
    if not PROJ_DOCS_DIR.exists():
        return mapping
    for p in PROJ_DOCS_DIR.glob("*"):
        if not p.is_file():
            continue
        name = p.name
        if "_" not in name:
            continue
        pref = name.split("_", 1)[0]
        if len(pref) == 10 and pref.isdigit():
            ts = int(pref)
            mapping.setdefault(ts, set()).add(p)
    return mapping

def _ensure_unique_projdocs_ts(ts: int, cur_path: Path, used: dict[int, set[Path]]) -> int:
    """Given desired timestamp prefix for a file under project_docs, decrement by 1 second
    repeatedly until it becomes unique among existing files (excluding the current file’s own
    occurrence). Returns the adjusted timestamp.
    """
    if cur_path.parent.resolve() != PROJ_DOCS_DIR.resolve():
        return ts
    cur_ts = ts
    while True:
        users = used.get(cur_ts, set())
        # Unique if set empty or only contains this file
        if not users or users == {cur_path}:
            break
        cur_ts -= 1
    # Reserve this ts for cur_path in mapping for subsequent files in this run
    used.setdefault(cur_ts, set()).add(cur_path)
    # If the file previously occupied another ts in 'used', clean it up to avoid false conflicts
    prev_pref = None
    name = cur_path.name
    if "_" in name and name.split("_", 1)[0].isdigit():
        prev_pref = int(name.split("_", 1)[0])
    if prev_pref is not None and prev_pref != cur_ts:
        s = used.get(prev_pref)
        if s and cur_path in s:
            s.discard(cur_path)
            if not s:
                used.pop(prev_pref, None)
    return cur_ts


def run_git(args: list[str]) -> str:
    return subprocess.check_output(["git", *args], text=True)


def first_add_timestamp(path: Path) -> int | None:
    """Return first add (A) commit timestamp for path, falling back to first commit."""
    try:
        out = run_git([
            "log",
            "--follow",
            "--diff-filter=A",
            "--format=%at",
            "--",
            str(path),
        ])
    except subprocess.CalledProcessError:
        out = ""
    ts = out.strip().splitlines()[-1] if out.strip() else ""
    if not ts:
        try:
            out = run_git(["log", "--follow", "--format=%at", "--", str(path)])
        except subprocess.CalledProcessError:
            out = ""
        ts = out.strip().splitlines()[-1] if out.strip() else ""
    return int(ts) if ts.isdigit() else None


def fmt_date_chs(ts: int) -> str:
    return time.strftime("%Y年%m月%d日", time.localtime(ts))


def fmt_date_iso(ts: int) -> str:
    return time.strftime("%Y-%m-%d", time.localtime(ts))


def ensure_date_in_markdown(md_path: Path, ts: int) -> bool:
    """Ensure the updated header block below the first H1:
    - 作者：GaoZheng
    - 日期：YYYY-MM-DD

    Also migrates legacy single-line date `日期：YYYY年MM月DD日` to the new two-line list.
    Returns True if file content changed.
    """
    try:
        text = md_path.read_text(encoding="utf-8")
    except Exception:
        return False
    lines = list(text.splitlines(True))
    title_idx = None
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("# "):
            title_idx = i
            break
    author_line = "- 作者：GaoZheng\n"
    date_line_new = f"- 日期：{fmt_date_iso(ts)}\n"
    date_line_old = f"日期：{fmt_date_chs(ts)}\n"
    changed = False
    if title_idx is None:
        # Prepend a synthetic title derived from filename (drop numeric prefix)
        stem = md_path.stem
        if "_" in stem and stem.split("_", 1)[0].isdigit():
            title = stem.split("_", 1)[1]
        else:
            title = stem
        new_text = f"# {title}\n{author_line}{date_line_new}\n" + text
        if new_text != text:
            md_path.write_text(new_text, encoding="utf-8")
            return True
        return False
    # Search a small window for an existing new-style author/date lines or legacy date
    win_start = title_idx + 1
    window_end = min(len(lines), title_idx + 6)
    patt_author = re.compile(r"^\s*-\s*作者[:：]")
    patt_date_new = re.compile(r"^\s*-\s*日期[:：]\s*\d{4}-\d{2}-\d{2}\s*$")
    patt_date_old = re.compile(r"^\s*日期[:：]\s*\d{4}年\d{2}月\d{2}日\s*$")

    idx_author = None
    idx_date_new = None
    idx_date_old = None
    for k in range(win_start, window_end):
        s = lines[k].strip()
        if idx_author is None and patt_author.match(s):
            idx_author = k
        if idx_date_new is None and patt_date_new.match(s):
            idx_date_new = k
        if idx_date_old is None and patt_date_old.match(s):
            idx_date_old = k
    # Migrate legacy date line to new two-line block
    if idx_date_old is not None and idx_date_new is None:
        # Replace old date with new lines, also ensure author exists before date
        # Remove old date line
        del lines[idx_date_old]
        # Recompute insertion pos just after title
        insert_pos = title_idx + 1
        # Insert author/date new (author first)
        lines.insert(insert_pos + 0, author_line)
        lines.insert(insert_pos + 1, date_line_new)
        changed = True
        # Clean potential duplicate author nearby
        # Re-scan a small range and collapse duplicates of author/date
    else:
        # Ensure author/date new lines exist and are correct
        # Author line
        if idx_author is None:
            lines.insert(win_start, author_line)
            changed = True
            # Shift known indices if needed
            if idx_date_new is not None:
                idx_date_new += 1
            if idx_date_old is not None:
                idx_date_old += 1
        # Date new line
        if idx_date_new is None:
            # If an old date exists, replace it with new-style
            if idx_date_old is not None:
                lines[idx_date_old] = date_line_new
                changed = True
                idx_date_new = idx_date_old
            else:
                # Insert right after author (or title if no author)
                insert_after = (idx_author if idx_author is not None else title_idx) + 1
                lines.insert(insert_after, date_line_new)
                changed = True
                idx_date_new = insert_after
        else:
            # Normalize the date value if mismatched
            if lines[idx_date_new] != date_line_new:
                lines[idx_date_new] = date_line_new
                changed = True
        # Normalize author text (ensure exact form)
        if idx_author is not None and lines[idx_author] != author_line:
            lines[idx_author] = author_line
            changed = True

    # Ensure there is exactly one blank line after the title before author/date
    if title_idx is not None:
        # Insert one blank if the next line is not blank
        nxt = title_idx + 1
        if nxt < len(lines) and lines[nxt].strip() != "":
            lines.insert(nxt, "\n")
            changed = True
        # Collapse multiple blanks to a single one between title and the first non-blank line
        j = title_idx + 1
        # Ensure at least one line exists after title
        if j < len(lines):
            # Move forward while there are consecutive blanks beyond one
            while j + 1 < len(lines) and lines[j].strip() == "" and lines[j + 1].strip() == "":
                del lines[j + 1]
                changed = True
    # Ensure there is a blank line after the date block
    # Determine end of header block (author + date)
    # Find indices again within small window
    idxs = []
    for k in range(title_idx + 1, min(len(lines), title_idx + 6)):
        s = lines[k].strip()
        if patt_author.match(s) or patt_date_new.match(s) or patt_date_old.match(s):
            idxs.append(k)
    if idxs:
        end_idx = max(idxs)
        # normalize to exactly one blank after date line
        # insert one blank if next is non-blank
        if end_idx + 1 < len(lines) and lines[end_idx + 1].strip() != "":
            lines.insert(end_idx + 1, "\n")
            changed = True
        # collapse multiple blanks to a single one
        while end_idx + 2 < len(lines) and lines[end_idx + 1].strip() == "" and lines[end_idx + 2].strip() == "":
            del lines[end_idx + 2]
            changed = True
    if changed:
        md_path.write_text("".join(lines), encoding="utf-8")
    return changed


def contains_o3_keyword(text: str) -> bool:
    low = text.lower()
    if "pfb-gnla" in low:
        return True
    return any(k in text for k in O3_KEYWORDS if k != "PFB-GNLA")


def ensure_o3_note(md_path: Path) -> bool:
    """Ensure the O3 reference note is placed directly below the date block.
    Priority:
      1) after new-style `- 日期：YYYY-MM-DD`
      2) else after legacy `日期：YYYY年MM月DD日`
      3) else after H1 title (synthesizes title/date if missing)
    Idempotent.
    """
    try:
        text = md_path.read_text(encoding="utf-8")
    except Exception:
        return False
    if not contains_o3_keyword(text):
        return False

    lines = text.splitlines(True)
    # Locate first H1 title
    title_idx = None
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("# "):
            title_idx = i
            break
    # Find date line near title
    date_pat_new = re.compile(r"^\s*-\s*日期[:：]\s*\d{4}-\d{2}-\d{2}\s*$")
    date_pat_old = re.compile(r"^\s*日期[:：]\s*\d{4}年\d{2}月\d{2}日\s*$")
    date_idx = None
    use_new = False
    if title_idx is not None:
        window_end = min(len(lines), title_idx + 6)
        for k in range(title_idx + 1, window_end):
            s = lines[k].strip()
            if date_pat_new.match(s):
                date_idx = k
                use_new = True
                break
        if date_idx is None:
            for k in range(title_idx + 1, window_end):
                s = lines[k].strip()
                if date_pat_old.match(s):
                    date_idx = k
                    break

    changed = False
    if title_idx is None or date_idx is None:
        # Fallback: synthesize heading/date at top
        name = md_path.name
        ts_val = None
        if "_" in name and name.split("_", 1)[0].isdigit():
            try:
                ts_val = int(name.split("_", 1)[0])
            except Exception:
                ts_val = None
        # Synthesize new-style header block
        date_line = f"- 日期：{fmt_date_iso(ts_val or int(time.time()))}\n"
        author_line = "- 作者：GaoZheng\n"
        title = md_path.stem
        new_lines = [f"# {title}\n", author_line, date_line, O3_NOTE, "\n"]
        new_lines.extend(lines)
        md_path.write_text("".join(new_lines), encoding="utf-8")
        return True

    # Remove existing O3 note instances (to keep single canonical copy)
    sig_substr = "O3理论/O3元数学理论/主纤维丛版广义非交换李代数(PFB-GNLA)"
    if any(sig_substr in ln for ln in lines):
        lines = [ln for ln in lines if sig_substr not in ln]
        changed = True
        # Recompute indices after removal
        title_idx = next((i for i, ln in enumerate(lines) if ln.lstrip().startswith("# ")), None)
        date_idx = None
        if title_idx is not None:
            window_end = min(len(lines), title_idx + 6)
            for k in range(title_idx + 1, window_end):
                s = lines[k].strip()
                if date_pat_new.match(s) or date_pat_old.match(s):
                    date_idx = k
                    break

    # Ensure exactly one blank line between date and O3 note
    base = (date_idx or 0)
    after = base + 1
    # if next is not blank, add one
    if after >= len(lines) or lines[after].strip() != "":
        lines.insert(after, "\n")
        changed = True
    # move insert position to just after the single blank
    insert_pos = base + 2
    lines.insert(insert_pos, O3_NOTE)
    # ensure exactly one blank after the note
    if insert_pos + 1 < len(lines) and lines[insert_pos + 1].strip() != "":
        lines.insert(insert_pos + 1, "\n")
    # collapse any extra blanks after note
    while insert_pos + 2 < len(lines) and lines[insert_pos + 1].strip() == "" and lines[insert_pos + 2].strip() == "":
        del lines[insert_pos + 2]
    changed = True
    if changed:
        md_path.write_text("".join(lines), encoding="utf-8")
    return changed


def normalize_h1_prefix(md_path: Path) -> bool:
    """If the first H1 line looks like "# <digits>_<title>", drop the numeric prefix.
    Returns True if the file was modified.
    """
    try:
        text = md_path.read_text(encoding="utf-8")
    except Exception:
        return False
    lines = text.splitlines(True)
    for i, ln in enumerate(lines):
        if ln.startswith("# "):
            m = re.match(r"^#\s+(\d{10})_(.+)$", ln.rstrip("\n"))
            if m:
                title_rest = m.group(2)
                lines[i] = f"# {title_rest}\n"
                md_path.write_text("".join(lines), encoding="utf-8")
                return True
            break
    return False


def normalize_h1_remove_title_label(md_path: Path) -> bool:
    """Remove a leading '标题：' or '标题:' label from the first H1 text.
    Returns True if changed.
    """
    try:
        text = md_path.read_text(encoding="utf-8")
    except Exception:
        return False
    lines = text.splitlines(True)
    for i, ln in enumerate(lines):
        if ln.startswith("# "):
            title = ln[2:].strip()
            for lab in ("标题：", "标题:", "標題：", "標題:"):
                if title.startswith(lab):
                    new_title = title[len(lab):].lstrip()
                    lines[i] = f"# {new_title}\n"
                    md_path.write_text("".join(lines), encoding="utf-8")
                    return True
            break
    return False

def cleanup_redundant_sections(md_path: Path) -> bool:
    """Remove redundant in-body sections like `### 标题` and `#### 摘要` that duplicate
    the normalized top matter. If a `#### 摘要` block exists and a top `## 摘要` block
    exists too, replace the top摘要内容 with the in-body one, then remove the in-body
    block. If top摘要不存在，则在头部后创建 `## 摘要` 并填入 in-body 摘要，再删除in-body块。

    Idempotent: re-running after cleanup makes no change.
    """
    try:
        text = md_path.read_text(encoding="utf-8")
    except Exception:
        return False
    lines = text.splitlines(True)

    changed = False

    # Locate H1 and top 摘要 block
    h1_idx = next((i for i, ln in enumerate(lines) if ln.lstrip().startswith("# ")), None)
    # Ensure exactly one blank line after H1 even if date normalization was skipped
    if h1_idx is not None:
        # Insert one blank if immediate next line is not blank
        nxt = h1_idx + 1
        if nxt < len(lines) and lines[nxt].strip() != "":
            lines.insert(nxt, "\n")
            changed = True
        # Collapse multiple blanks after title to a single one
        j = h1_idx + 1
        while j + 1 < len(lines) and lines[j].strip() == "" and lines[j + 1].strip() == "":
            del lines[j + 1]
            changed = True
    top_summary_idx = None
    if h1_idx is not None:
        # search for '## 摘要' within next ~10 lines
        for k in range(h1_idx + 1, min(len(lines), h1_idx + 12)):
            if lines[k].lstrip().startswith("## ") and ("摘要" in lines[k]):
                top_summary_idx = k
                break

    # Helper: find block end index starting from a given start (exclusive),
    # stopping at next heading (#), or horizontal rule, or end of file.
    def _find_block_end(start_idx: int) -> int:
        i = start_idx + 1
        while i < len(lines):
            s = lines[i].strip()
            if s.startswith("#"):
                break
            if s == "---" or s == "***":
                break
            i += 1
        return i

    # 1) Remove any '### 标题' section headings (and optionally its immediate blank line)
    i = 0
    to_delete_ranges: list[tuple[int, int]] = []
    while i < len(lines):
        s = lines[i].lstrip()
        if s.startswith("###") and ("标题" in s):
            # Delete only the heading line; if next is empty, delete it too
            j = i + 1
            if j < len(lines) and lines[j].strip() == "":
                to_delete_ranges.append((i, j + 1))
                i = j + 1
            else:
                to_delete_ranges.append((i, i + 1))
                i = i + 1
            changed = True
            continue
        i += 1

    # 2) Capture and remove an in-body '#### 摘要' block
    abstract_block: list[str] | None = None
    abs_start = abs_end = None
    for i in range(0, len(lines)):
        s = lines[i].lstrip()
        if s.startswith("####") and ("摘要" in s):
            abs_start = i
            abs_end = _find_block_end(i)
            abstract_block = [ln for ln in lines[i + 1:abs_end]]
            to_delete_ranges.append((abs_start, abs_end))
            changed = True
            break

    # Apply deletions (from bottom to top to preserve indices)
    if to_delete_ranges:
        for (a, b) in sorted(to_delete_ranges, key=lambda x: x[0], reverse=True):
            del lines[a:b]

    # If we captured an abstract and have a top 摘要 block, replace its content
    if abstract_block is not None:
        # Normalize: ensure abstract text block ends with a newline and one blank line
        while abstract_block and abstract_block[0].strip() == "":
            abstract_block.pop(0)
        while abstract_block and abstract_block[-1].strip() == "":
            abstract_block.pop()
        insert_payload = ["\n"] + abstract_block + ["\n", "\n"] if abstract_block else ["\n", "(自动合并的摘要占位)\n", "\n"]

        # Recompute h1/top summary indices after deletions
        h1_idx = next((i for i, ln in enumerate(lines) if ln.lstrip().startswith("# ")), None)
        top_summary_idx = None
        if h1_idx is not None:
            for k in range(h1_idx + 1, min(len(lines), h1_idx + 12)):
                if lines[k].lstrip().startswith("## ") and ("摘要" in lines[k]):
                    top_summary_idx = k
                    break

        if top_summary_idx is None and h1_idx is not None:
            # Create a new top 摘要 block after the header block (author/date/O3 note, skipping blanks)
            ins = h1_idx + 1
            # Skip author/date bullets and O3 note + trailing blank lines
            for _ in range(8):
                if ins < len(lines) and (lines[ins].lstrip().startswith("- 作者：") or lines[ins].lstrip().startswith("- 日期：") or lines[ins].lstrip().startswith("#### ***") or lines[ins].strip() == ""):
                    ins += 1
                else:
                    break
            block = ["## 摘要\n"] + insert_payload[1:]  # ensure exactly one leading blank after header line
            lines[ins:ins] = block
            changed = True
        elif top_summary_idx is not None:
            # Replace content under existing '## 摘要' until next heading
            start = top_summary_idx + 1
            end = _find_block_end(top_summary_idx)
            # Ensure there is exactly one blank line after header line '## 摘要'
            lines[start:end] = insert_payload
            changed = True

    # Enforce exactly one blank line between date bullet and O3 note (#### ***)
    # This is independent of localized labels and relies on ISO date pattern
    try:
        date_bullet_idx = next(
            (i for i, ln in enumerate(lines)
             if ln.lstrip().startswith("- ") and re.search(r"\d{4}-\d{2}-\d{2}\s*$", ln)),
            None,
        )
    except Exception:
        date_bullet_idx = None
    try:
        o3_note_idx = next((i for i, ln in enumerate(lines) if ln.lstrip().startswith("#### ***")), None)
    except Exception:
        o3_note_idx = None
    if date_bullet_idx is not None and o3_note_idx is not None and o3_note_idx > date_bullet_idx:
        # Ensure single blank line exists at date_bullet_idx + 1
        after = date_bullet_idx + 1
        if after >= len(lines) or lines[after].strip() != "":
            lines.insert(after, "\n")
            changed = True
            o3_note_idx += 1
        # Collapse extra blanks between date and note
        while o3_note_idx - date_bullet_idx > 2 and lines[after + 1].strip() == "":
            del lines[after + 1]
            changed = True


    # Ensure no blank between author and date bullets
    try:
        au_idx = next((i for i, ln in enumerate(lines) if ln.lstrip().startswith("- 作者：")), None)
        dt_idx = next((i for i, ln in enumerate(lines) if re.match(r"^\s*-\s*日期[:：]\\s*\\d{4}-\\d{2}-\\d{2}\\s*$", ln.strip())), None)
    except Exception:
        au_idx = None; dt_idx = None
    if au_idx is not None and dt_idx is not None and dt_idx > au_idx:
        # if a single blank line exists between them, remove it
        if au_idx + 1 < len(lines) and lines[au_idx + 1].strip() == "" and au_idx + 2 == dt_idx:
            del lines[au_idx + 1]
            changed = True

    # Ensure '## 摘要' is immediately followed by content (no blank line)
    try:
        top_summary_idx = next((i for i, ln in enumerate(lines) if ln.lstrip().startswith("## ") and ("摘要" in ln or "ժҪ" in ln)), None)
    except Exception:
        top_summary_idx = None
    if top_summary_idx is not None:
        if top_summary_idx + 1 < len(lines) and lines[top_summary_idx + 1].strip() == "":
            del lines[top_summary_idx + 1]
            changed = True

    # Remove in-body H3 title that duplicates the H1 title
    try:
        h1_idx = next((i for i, ln in enumerate(lines) if ln.lstrip().startswith("# ")), None)
    except Exception:
        h1_idx = None
    if h1_idx is not None:
        h1_title = lines[h1_idx].lstrip()[2:].strip()
        dup_variants = {f"### {h1_title}", f"### **{h1_title}**"}
        start_scan = h1_idx + 1
        end_scan = min(len(lines), start_scan + 200)
        for i in range(start_scan, end_scan):
            s = lines[i].strip()
            if any(s.startswith(v) for v in dup_variants):
                del lines[i]
                # collapse extra consecutive blanks
                while i < len(lines) - 1 and lines[i].strip() == "" and lines[i + 1].strip() == "":
                    del lines[i + 1]
                changed = True
                break
    # Ensure a horizontal rule '---' after the 摘要 block, with single blanks around
    try:
        top_summary_idx = next((i for i, ln in enumerate(lines) if ln.lstrip().startswith("## ") and ("摘要" in ln or "ժҪ" in ln or "??" in ln)), None)
    except Exception:
        top_summary_idx = None
    if top_summary_idx is not None:
        # Determine end boundary of the summary block
        start = top_summary_idx + 1
        # Skip a potential accidental blank just in case
        while start < len(lines) and lines[start].strip() == "":
            start += 1
        end = start
        while end < len(lines):
            s = lines[end].strip()
            if s.startswith("#") or s == "---" or s == "***":
                break
            end += 1
        # Find last non-empty line in the summary content
        last = end - 1
        while last >= start and lines[last].strip() == "":
            last -= 1
        if last >= start:
            # Check for existing HR at 'end'
            has_hr = (end < len(lines) and lines[end].strip() in ("---", "***"))
            if has_hr:
                # Standardize to '---' and spacing: one blank before and after
                if lines[end].strip() != "---":
                    lines[end] = "---\n"
                    changed = True
                # Ensure exactly one blank between summary content and HR
                if not (end - (last + 1) == 1 and lines[last + 1].strip() == ""):
                    # Replace region with a single blank
                    del lines[last + 1:end]
                    lines.insert(last + 1, "\n")
                    changed = True
                # Re-find HR index (may shift after edits)
                hr_idx = None
                for ii in range(last + 1, min(len(lines), last + 8)):
                    if lines[ii].strip() == "---":
                        hr_idx = ii
                        break
                if hr_idx is None:
                    for ii in range(top_summary_idx + 1, len(lines)):
                        if lines[ii].strip() == "---":
                            hr_idx = ii
                            break
                if hr_idx is not None:
                    # Ensure exactly one blank after HR
                    if hr_idx + 1 >= len(lines) or lines[hr_idx + 1].strip() != "":
                        lines.insert(hr_idx + 1, "\n")
                        changed = True
                    # Collapse extra blanks after HR to a single one
                    while hr_idx + 2 < len(lines) and lines[hr_idx + 1].strip() == "" and lines[hr_idx + 2].strip() == "":
                        del lines[hr_idx + 2]
                        changed = True
            else:
                # Insert HR with single-blank padding
                insert_at = last + 1
                lines.insert(insert_at, "\n")
                lines.insert(insert_at + 1, "---\n")
                lines.insert(insert_at + 2, "\n")
                changed = True
            changed = True
    if changed:
        md_path.write_text("".join(lines), encoding="utf-8")
    return changed


def ensure_author_bullet(md_path: Path, author: str = "GaoZheng") -> bool:
    try:
        text = md_path.read_text(encoding="utf-8")
    except Exception:
        return False
    lines = text.splitlines(True)
    changed = False
    # find H1
    h1_idx = next((i for i, ln in enumerate(lines) if ln.lstrip().startswith("# ")), None)
    if h1_idx is None:
        return False
    # find author bullet within next few lines
    patt_author = re.compile(r"^\s*-\s*作者[:：]")
    has_author = any(patt_author.match(lines[i].strip()) for i in range(h1_idx + 1, min(len(lines), h1_idx + 6)))
    if not has_author:
        # ensure one blank after title
        ins = h1_idx + 1
        if ins < len(lines) and lines[ins].strip() != "":
            lines.insert(ins, "\n")
            ins += 1
            changed = True
        # insert author bullet
        lines.insert(ins, f"- 作者：{author}\n")
        changed = True
        # ensure there is at least one line after author; date bullet fixer may run later
    if changed:
        md_path.write_text("".join(lines), encoding="utf-8")
    return changed
def iter_target_files() -> list[Path]:
    files: list[Path] = []
    # my_docs/**
    docs_root = ROOTS[0]
    if docs_root.exists():
        files.extend([p for p in docs_root.rglob("*") if p.is_file() and _is_allowed(p)])
    # my_project/**/docs/**
    proj_root = ROOTS[1]
    if proj_root.exists():
        for p in proj_root.rglob("*"):
            if not p.is_file():
                continue
            if "docs" in p.parts:
                if _is_allowed(p):
                    files.append(p)
    return files


def main() -> int:
    renamed: list[str] = []
    dated: list[str] = []
    noted: list[str] = []
    targets = iter_target_files()
    # Track used prefixes within my_docs/project_docs to guarantee uniqueness
    used_proj_prefixes = _scan_project_docs_prefixes()
    # Pre-reserve original timestamp for lexicographically smallest title when
    # multiple files share the same 10-digit prefix under project_docs.
    for ts, paths in list(used_proj_prefixes.items()):
        if len(paths) > 1:
            try:
                def _title_key(p: Path) -> str:
                    name = p.name
                    rest = name.split("_", 1)[1] if "_" in name else name
                    return rest
                first = sorted(paths, key=_title_key)[0]
                used_proj_prefixes[ts] = {first}
            except Exception:
                # If sorting fails for any reason, keep original set; unique enforcement will still work
                pass
    if not targets:
        print("No target files found under my_docs/ or my_project/**/docs")
        return 0
    for p in targets:
        name = p.name
        ts_use: int | None = None
        if "_" in name:
            prefix, rest = name.split("_", 1)
            if prefix.isdigit():
                ts_filename = int(prefix)
                exempt = (
                    p.as_posix().startswith("my_docs/project_docs/")
                    and ts_filename in EXEMPT_PREFIXES
                )
                if exempt:
                    # Reserve current prefix to prevent others from taking it; do not change it
                    used_proj_prefixes.setdefault(ts_filename, set()).add(p)
                    ts_use = ts_filename
                else:
                    ts_git = first_add_timestamp(p)
                    if ts_git is not None:
                        # Strip unwanted '标题：'/'标题:' prefix from the title part of filename
                        rest_stripped = rest
                        for lab in ("标题：", "标题:", "標題：", "標題:"):
                            if rest_stripped.startswith(lab):
                                rest_stripped = rest_stripped[len(lab):].lstrip()
                                break
                        # Enforce unique prefix under project_docs by stepping back seconds if needed
                        ts_final = _ensure_unique_projdocs_ts(ts_git, p, used_proj_prefixes)
                        # 1) rename if needed
                        new_name = f"{ts_final}_{rest_stripped}"
                        if new_name != name:
                            new_path = p.with_name(new_name)
                            subprocess.check_call(["git", "mv", "-f", "--", str(p), str(new_path)])
                            p = new_path
                            name = p.name
                            renamed.append(str(new_path))
                        ts_use = ts_final
        # 2) ensure date line in markdown
        if p.suffix.lower() == ".md" and ts_use is not None:
            if ensure_date_in_markdown(p, ts_use):
                dated.append(str(p))
            if normalize_h1_prefix(p):
                # treat as date-updated category for reporting simplicity
                if str(p) not in dated:
                    dated.append(str(p))
        # 3) ensure O3 note when keywords present (markdown only)
        if p.suffix.lower() == ".md":
            if ensure_o3_note(p):
                noted.append(str(p))
            # 4) Always normalize H1 to drop timestamp prefix if present
            normalize_h1_prefix(p)
            # 4.1) Remove leading '标题：'/'标题:' label from H1
            normalize_h1_remove_title_label(p)
            # 5) Cleanup redundant sections and enforce header spacing even if date step skipped
            cleanup_redundant_sections(p)
            # 6) Ensure author bullet exists (default GaoZheng)
            ensure_author_bullet(p)
    print(f"Renamed {len(renamed)} file(s)")
    for f in renamed:
        print(" -", f)
    print(f"Updated date in {len(dated)} markdown file(s)")
    for f in dated:
        print(" -", f)
    print(f"Inserted O3 note in {len(noted)} markdown file(s)")
    for f in noted:
        print(" -", f)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

