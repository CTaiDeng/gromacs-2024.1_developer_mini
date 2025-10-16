#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2025 GaoZheng
#
# This is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation, version 3. This software is distributed in the hope that it will
# be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
# Public License for more details. You should have received a copy of the GNU
# General Public License along with this program. If not, see:
# https://www.gnu.org/licenses/gpl-3.0.html

"""
核心知识库更新脚本（只写入 kernel_reference）

步骤：
1) 先检查并清空 my_docs/project_docs/kernel_reference（不存在则创建）
2) git clone --sparse --filter=blob:none --branch master --single-branch \
      https://github.com/CTaiDeng/open_meta_mathematical_theory.git out/kernel_reference_only
3) 在 out/kernel_reference_only 下执行：git sparse-checkout set src/kernel_reference
4) 将 out/kernel_reference_only/src/kernel_reference 的内容复制到 my_docs/project_docs/kernel_reference
5) 删除临时目录 out/kernel_reference_only

注意：本脚本仅写入 my_docs/project_docs/kernel_reference（外部参考只读目录的更新例外）。
"""

from __future__ import annotations

import os
import shutil
import stat
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
KERNEL_REF_DIR = ROOT / "my_docs" / "project_docs" / "kernel_reference"
TMP_OUT_DIR = ROOT / "out" / "kernel_reference_only"


def _run(cmd: list[str]) -> None:
    res = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(
            f"Command failed: {' '.join(cmd)}\nstdout:\n{res.stdout}\nstderr:\n{res.stderr}"
        )


def _ensure_git_available() -> None:
    try:
        subprocess.run(["git", "--version"], check=True, capture_output=True)
    except Exception as exc:
        raise RuntimeError(
            "未检测到 git，请安装后再运行该脚本，并确保 git 在 PATH 中。"
        ) from exc


def _empty_directory_keep_root(dir_path: Path) -> None:
    dir_path.mkdir(parents=True, exist_ok=True)
    for child in dir_path.iterdir():
        if child.is_dir():
            _rmtree_force(child)
        else:
            try:
                child.unlink()
            except FileNotFoundError:
                pass


def _copy_tree_contents(src: Path, dst: Path) -> None:
    dst.mkdir(parents=True, exist_ok=True)
    for child in src.iterdir():
        target = dst / child.name
        if child.is_dir():
            # Python 3.8+: dirs_exist_ok
            try:
                shutil.copytree(child, target, dirs_exist_ok=True)
            except TypeError:
                # Fallback for older Python: manual merge
                if not target.exists():
                    shutil.copytree(child, target)
                else:
                    _copy_tree_contents(child, target)
        else:
            shutil.copy2(child, target)


# ---- 辅助函数：更强健的删除，解决 Windows 只读/占用问题 ----
def _on_rm_error(func, path, exc_info):
    try:
        os.chmod(path, stat.S_IWRITE)
    except Exception:
        pass
    try:
        func(path)
    except Exception:
        pass


def _rmtree_force(path: Path, retries: int = 3, delay: float = 0.3) -> None:
    """强制删除文件/目录；若不存在则忽略。

    在 Windows/WSL 环境下，文件可能带只读属性或被占用，
    这里通过 chmod + 重试 提升鲁棒性。
    """
    if not path.exists():
        return
    # 如果是文件/链接，优先尝试直接删除
    if path.is_file() or path.is_symlink():
        try:
            os.chmod(path, stat.S_IWRITE)
        except Exception:
            pass
        try:
            path.unlink()
            return
        except Exception:
            # 继续尝试用 rmtree 处理
            pass
    for _ in range(retries):
        try:
            shutil.rmtree(path, onerror=_on_rm_error)
        except FileNotFoundError:
            return
        except Exception:
            time.sleep(delay)
        if not path.exists():
            return
        time.sleep(delay)
    # 仍未删除成功则给出明确提示
    if path.exists():
        try:
            remaining = len(list(path.iterdir()))
        except Exception:
            remaining = -1
        raise RuntimeError(
            f"无法删除目录：{path}。请关闭占用该目录的程序（资源管理器/杀毒/编辑器）后重试。剩余条目：{remaining}"
        )


def main() -> None:
    _ensure_git_available()

    print(f"[1/5] 清空目录: {KERNEL_REF_DIR}")
    _empty_directory_keep_root(KERNEL_REF_DIR)

    # 无论是否存在，都尝试强制清理，避免 Windows 下只读/占用导致残留
    print(f"[2/5] 清理已有临时目录: {TMP_OUT_DIR}")
    _rmtree_force(TMP_OUT_DIR)

    print("[3/5] 稀疏克隆远端仓库（仅 master 分支）...")
    _run([
        "git",
        "clone",
        "--sparse",
        "--filter=blob:none",
        "--branch",
        "master",
        "--single-branch",
        "https://github.com/CTaiDeng/open_meta_mathematical_theory.git",
        str(TMP_OUT_DIR),
    ])

    print("[4/5] 设置 sparse-checkout: src/kernel_reference")
    _run(["git", "-C", str(TMP_OUT_DIR), "sparse-checkout", "set", "src/kernel_reference"])

    src_dir = TMP_OUT_DIR / "src" / "kernel_reference"
    if not src_dir.exists():
        # 清理临时目录后再报错
        try:
            shutil.rmtree(TMP_OUT_DIR, ignore_errors=True)
        finally:
            raise FileNotFoundError(f"未在临时仓库中找到期望目录: {src_dir}")

    print(f"[5/5] 拷贝内容到: {KERNEL_REF_DIR}")
    _copy_tree_contents(src_dir, KERNEL_REF_DIR)

    print("[清理] 删除临时目录 out/kernel_reference_only")
    _rmtree_force(TMP_OUT_DIR)

    print("完成：my_docs/project_docs/kernel_reference 已更新。")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("中断执行。")
        raise
