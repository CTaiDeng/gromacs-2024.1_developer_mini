#!/usr/bin/env bash
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.
set -euo pipefail

# 在 WSL(Ubuntu/Debian) 下为当前机器安装 acpype 依赖：AmberTools(antechamber) 与 Open Babel。
# - 使用 conda 在指定环境安装（默认环境名：amber）。
# - 无需激活环境，脚本用 `conda run` 验证 antechamber 可用性。
#
# 先决条件：已安装 Conda/Miniforge/Mambaforge，并已初始化到 shell。
# 如未安装，建议：
#   wget https://github.com/conda-forge/miniforge/releases/latest/download/Mambaforge-Linux-x86_64.sh -O ~/mambaforge.sh
#   bash ~/mambaforge.sh -b -p $HOME/mambaforge
#   source "$HOME/mambaforge/etc/profile.d/conda.sh"
#   conda config --set channel_priority strict
#   conda config --add channels conda-forge

ENV_NAME="amber"
WITH_OPENBABEL=1

usage() {
  cat <<EOF
用法: $(basename "$0") [选项]
  --env <name>        Conda 环境名（默认：amber）
  --no-openbabel      不安装 openbabel（默认安装）
  -h, --help          显示帮助

示例：
  bash my_scripts/install_amber_deps_wsl.sh --env amber
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env) ENV_NAME="$2"; shift 2;;
    --no-openbabel) WITH_OPENBABEL=0; shift;;
    -h|--help) usage; exit 0;;
    *) echo "[ERR] 未知参数: $1" >&2; usage; exit 1;;
  esac
done

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "[ERR] 缺少依赖：$1" >&2; exit 1; }
}

need_cmd conda

# 确保使用 conda-forge 通道（若用户未配置，显式传参即可）
PKGS=(ambertools)
if [[ $WITH_OPENBABEL -eq 1 ]]; then PKGS+=(openbabel); fi

echo "[INFO] 检查环境是否存在: $ENV_NAME"
if conda env list | awk '{print $1}' | grep -Fxq "$ENV_NAME"; then
  echo "[INFO] 已存在环境 $ENV_NAME，直接安装/更新依赖"
else
  echo "[INFO] 创建环境 $ENV_NAME"
  conda create -n "$ENV_NAME" -y -c conda-forge python=3.11
fi

echo "[INFO] 安装 AmberTools/Open Babel 到环境 $ENV_NAME"
conda install -n "$ENV_NAME" -y -c conda-forge "${PKGS[@]}"

echo "[INFO] 验证 antechamber 可用性"
conda run -n "$ENV_NAME" antechamber -h >/dev/null
echo "[DONE] antechamber 已可用于环境: $ENV_NAME"

if [[ $WITH_OPENBABEL -eq 1 ]]; then
  conda run -n "$ENV_NAME" obabel -V >/dev/null || true
  echo "[DONE] openbabel 已安装（如需 SMILES->3D 转换将自动可用）"
fi

cat <<EOT

接下来：
  1) 激活环境：   conda activate $ENV_NAME
  2) 生成 mol2：  bash my_scripts/generate_hiv_mol2_wsl.sh --smiles "C1=CC=CC=C1C(=O)N" --charge 0 --resname LIG --out hiv.mol2
  3) 转换为 GROMACS 拓扑： acpype -i hiv.mol2 -b LIG -o gmx

若不想每次激活，可用 conda run：
  conda run -n $ENV_NAME bash my_scripts/generate_hiv_mol2_wsl.sh --input lig.pdb --charge 0 --resname LIG --out hiv.mol2
EOT
