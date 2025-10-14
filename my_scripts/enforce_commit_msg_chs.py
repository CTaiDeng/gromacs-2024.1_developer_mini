#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.

"""
commit-msg enforcement: require Simplified Chinese commit messages.
Rules:
- Must contain at least one CJK Unified Ideograph (\u4e00-\u9fff)
- Must not contain obviously Traditional-only characters (heuristic list)
- Ignore comment lines starting with '#'
Exits non-zero to block commit when violation occurs.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path


TRADITIONAL_CHARS = set(
    # Common Traditional forms that should be Simplified in this project
    "體國臺龐廣聯術務產學實歷參與準驗電顯導證錯變構與國際網絡軟體對齊擴覽穩讀絕聲顧訊據雲數據庫鏈銷臺灣醫藥劑戶內隨碼開發龍關係經濟藝術標題"
)


def load_message(msg_path: Path) -> str:
    try:
        text = msg_path.read_text(encoding="utf-8", errors="ignore")
    except Exception:
        text = msg_path.read_text(errors="ignore")
    # strip comment lines and CRLF
    lines: list[str] = []
    for ln in text.splitlines():
        if ln.lstrip().startswith("#"):
            continue
        lines.append(ln.rstrip("\r"))
    return "\n".join(lines).strip()


def contains_cjk(s: str) -> bool:
    return bool(re.search(r"[\u4e00-\u9fff]", s))


def contains_traditional(s: str) -> str | None:
    for ch in s:
        if ch in TRADITIONAL_CHARS:
            return ch
    return None


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print("[commit-msg] 缺少参数：未提供提交信息文件路径", file=sys.stderr)
        return 1
    msg_file = Path(argv[1])
    content = load_message(msg_file)
    if not content:
        print("[commit-msg] 提交信息不能为空，且必须使用简体中文。", file=sys.stderr)
        return 1

    if not contains_cjk(content):
        print("[commit-msg] 提交信息必须为简体中文，且至少包含一个中文字符。", file=sys.stderr)
        return 1

    bad = contains_traditional(content)
    if bad is not None:
        print(
            f"[commit-msg] 检测到疑似繁体字‘{bad}’，请使用简体中文后再提交。",
            file=sys.stderr,
        )
        return 1

    # Passed
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
