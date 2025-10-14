#!/usr/bin/env bash
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.
set -euo pipefail

# 将对接复合物按配体/受体分离：生成 ligand.pdb 和 receptor.pdb
# 依赖：GROMACS 可执行程序在 PATH 中（命令名 `gmx`），或通过环境变量 GMX_BIN 指定路径。
# 默认输入：仓库根目录下的 res/hiv.pdb，默认配体残基名 CSO。

complex_pdb="res/hiv.pdb"
ligand_res="CSO"

usage() {
  cat <<EOF
用法：$(basename "$0") [选项]
  -i, --complex <pdb>   复合物 PDB 文件（默认：res/hiv.pdb）
  -r, --resname <name>  配体残基名（默认：CSO）
  -h, --help            显示帮助

示例：
  bash my_scripts/example/gmx_split_docking.sh -i res/hiv.pdb -r LIG
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--complex) complex_pdb="$2"; shift 2;;
    -r|--resname) ligand_res="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "未知参数: $1" >&2; usage; exit 1;;
  esac
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$script_dir/.." && pwd)

# 选择 gmx 可执行程序
gmx_bin=${GMX_BIN:-gmx}
if [[ "$gmx_bin" != /* ]]; then
  if ! command -v "$gmx_bin" >/dev/null 2>&1; then
    echo "未找到 GROMACS 命令：$gmx_bin（可设置 GMX_BIN 指定）" >&2
    exit 1
  fi
fi

# 解析输入路径（相对路径相对于仓库根目录）
if [[ "$complex_pdb" = /* ]]; then
  complex_candidate="$complex_pdb"
else
  complex_candidate="$root/$complex_pdb"
fi
if [[ ! -f "$complex_candidate" ]]; then
  echo "输入坐标文件不存在：$complex_candidate" >&2
  exit 1
fi

out_root="$root/out"
mkdir -p "$out_root"
job_dir="$out_root/gmx_split_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$job_dir"
echo "工作目录：$job_dir"

complex_copy="$job_dir/$(basename "$complex_candidate")"
cp -f "$complex_candidate" "$complex_copy"
complex_input="$complex_copy"

complex_gro="$job_dir/complex.gro"
ligand_ndx="$job_dir/ligand.ndx"
ligand_pdb="$job_dir/ligand.pdb"
receptor_ndx="$job_dir/receptor.ndx"
receptor_pdb="$job_dir/receptor.pdb"

# 1) PDB -> GRO
"$gmx_bin" editconf -f "$complex_input" -o "$complex_gro" >/dev/null

# 2) 选择配体并导出 PDB
"$gmx_bin" select -f "$complex_gro" -s "$complex_gro" -on "$ligand_ndx" -select "resname $ligand_res" >/dev/null
printf "0\n" | "$gmx_bin" trjconv -f "$complex_gro" -s "$complex_gro" -o "$ligand_pdb" -n "$ligand_ndx" -dump 0 >/dev/null

# 3) 选择受体（非配体）并导出 PDB
"$gmx_bin" select -f "$complex_gro" -s "$complex_gro" -on "$receptor_ndx" -select "not resname $ligand_res" >/dev/null
printf "0\n" | "$gmx_bin" trjconv -f "$complex_gro" -s "$complex_gro" -o "$receptor_pdb" -n "$receptor_ndx" -dump 0 >/dev/null

echo "已复制原始结构到：$complex_copy"
echo "配体坐标：$ligand_pdb"
echo "受体坐标：$receptor_pdb"
