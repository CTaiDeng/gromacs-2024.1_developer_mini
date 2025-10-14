#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.

from __future__ import annotations

import re
import subprocess
import time
from pathlib import Path


FILES = [
    "my_docs/project_docs/1752417159_药理学的代数形式化：一个作用于基因组的算子体系.md",
    "my_docs/project_docs/1752417160_论药理学干预的代数结构：药理基因组算子幺半群（PGOM）的形式化.md",
    "my_docs/project_docs/1752417161_从物理实在到代数干预：论PFB-GNLA向PGOM的平庸化退化.md",
    "my_docs/project_docs/1752417162_O3理论下的本体论退化：从流变实在到刚性干预——论PFB-GNLA向PGOM的逻辑截面投影.md",
    "my_docs/project_docs/1752417163_论O3理论的自相似动力学：作为递归性子系统 GRL 路径积分的 PGOM.md",
    "my_docs/project_docs/1752417164_PGOM作为元理论：生命科学各分支的算子幺半群构造.md",
    "my_docs/project_docs/1752417165_论六大生命科学代数结构的幺半群完备性：基于元素与子集拓扑的双重视角分析.md",
    "my_docs/project_docs/1752417166_LBOPB的全息宇宙：生命系统在六个不同观测参考系下的完整论述.md",
    "my_docs/project_docs/1752417167_同一路径，六重宇宙：论HIV感染与治疗的GRL路径积分在LBOPB六大参考系下的全息解释.md",
    "my_docs/project_docs/1752417168_计算化学的O3理论重构：作为PDEM幺半群内在动力学的多尺度计算引擎.md",
]

TARGET_DATE = (2025, 9, 29)  # Y, M, D


def run(cmd: list[str]) -> None:
    subprocess.check_call(cmd)


def new_ts_from_old(old_ts: int) -> int:
    tm = time.localtime(old_ts)
    y, m, d = TARGET_DATE
    # Preserve h:m:s from old ts, use local time
    t = (y, m, d, tm.tm_hour, tm.tm_min, tm.tm_sec, 0, 0, -1)
    return int(time.mktime(t))


def update_date_line(p: Path) -> None:
    try:
        text = p.read_text(encoding="utf-8")
    except Exception:
        return
    lines = text.splitlines(True)
    # Find and replace 日期 line
    import re as _re

    date_pat = _re.compile(r"^(\s*)日期[:：]\s*\d{4}年\d{2}月\d{2}日\s*$")
    replaced = False
    for i, ln in enumerate(lines):
        m = date_pat.match(ln.strip())
        if m:
            lines[i] = "日期：2025年09月29日\n"
            replaced = True
            break
    if not replaced:
        # Insert under first H1
        for i, ln in enumerate(lines):
            if ln.lstrip().startswith("# "):
                lines.insert(i + 1, "日期：2025年09月29日\n")
                lines.insert(i + 2, "\n")
                replaced = True
                break
    if replaced:
        p.write_text("".join(lines), encoding="utf-8")


def main() -> int:
    mapping: list[tuple[int, int, Path, Path]] = []
    for s in FILES:
        p = Path(s)
        if not p.exists():
            print("skip (missing):", s)
            continue
        m = re.match(r"^(\d{10})_(.+)$", p.name)
        if not m:
            print("skip (no ts prefix):", s)
            continue
        old_ts = int(m.group(1))
        rest = m.group(2)
        nts = new_ts_from_old(old_ts)
        new_name = f"{nts}_{rest}"
        new_path = p.with_name(new_name)
        if new_path != p:
            run(["git", "mv", "-f", "--", str(p), str(new_path)])
        update_date_line(new_path)
        mapping.append((old_ts, nts, p, new_path))

    print("Updated timestamps (old -> new):")
    for old_ts, nts, _oldp, newp in mapping:
        print(f" - {old_ts} -> {nts} :: {newp}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
