#!/usr/bin/env bash
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.
set -Eeuo pipefail

# ===== 调试与日志 =====
: "${DEBUG:=1}"
: "${OBABEL_TIMEOUT_SEC:=600}"
: "${LOG_DIR:=logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/generate_hiv_mol2_wsl.$(date +%Y%m%d_%H%M%S).log"

log_info()  { printf "[INFO] %s\n" "$*"; }
log_warn()  { printf "[WARN] %s\n" "$*"; }
log_err()   { printf "[ERR ] %s\n"  "$*" 1>&2; }
log_debug() { [[ "$DEBUG" = 1 ]] && printf "[DBG ] %s\n" "$*"; true; }

_start_ts=$(date +%s 2>/dev/null || echo 0)
trap 'rc=$?; _end_ts=$(date +%s 2>/dev/null || echo 0); dur=$(( _end_ts-_start_ts ));
      if (( rc==0 )); then log_info "脚本完成，耗时 ${dur}s"; else log_err "脚本失败(rc=$rc)，耗时 ${dur}s"; fi' EXIT

# 将全部输出同时写入日志
exec > >(tee -a "$LOG_FILE") 2>&1

if [[ "$DEBUG" = 1 ]]; then
  export PS4='[TRACE] ${BASH_SOURCE##*/}:${LINENO}(${FUNCNAME[0]:-main}) '
  set -x
fi

log_debug "LD_PRELOAD=${LD_PRELOAD-}"
log_debug "LD_LIBRARY_PATH=${LD_LIBRARY_PATH-}"

log_info "日志文件：$LOG_FILE"
log_debug "日期：$(date)"
log_debug "内核：$(uname -a)"
if command -v lsb_release >/dev/null 2>&1; then log_debug "发行版：$(lsb_release -ds)"; fi
if grep -qi microsoft /proc/version 2>/dev/null; then log_debug "检测到 WSL 环境"; fi
if command -v conda >/dev/null 2>&1; then log_debug "conda 环境：$(conda info --envs 2>/dev/null | sed -n '1,80p')"; fi

# 说明：
# - 在 WSL(Ubuntu/Debian) 下，从 SMILES 或输入结构文件生成标准的 hiv.mol2
# - 优先通过 Open Babel 生成3D坐标（SDF），再用 antechamber 输出 Tripos mol2（含 SUBSTRUCTURE、残基名）
# - 需要的工具：antechamber（AmberTools），建议安装 openbabel（处理 SMILES/2D 转 3D）
#
# 先决条件（conda 环境示例）：
#   conda create -n amber -c conda-forge ambertools openbabel -y
#   conda activate amber
#
# 用法：
#   bash my_scripts/generate_hiv_mol2_wsl.sh [选项]
#
# 选项：
#   --input <file>     输入结构文件（mol2/sdf/pdb/mol 等），若是2D建议安装 openbabel
#   --smiles <str>     直接指定 SMILES 字符串（需 openbabel）
#   --resname <name>   残基名（默认：LIG）
#   --charge <int>     净电荷（默认：0）
#   --out <file>       输出文件（默认：hiv.mol2）
#   --ph <float>       生成3D时假定的 pH（默认：7.4，仅 openbabel 用）
#   -h, --help         显示帮助
#
# 示例：
#   # 从 SMILES 直接生成 hiv.mol2（中性，残基名 LIG）
#   bash my_scripts/generate_hiv_mol2_wsl.sh --smiles "c1ccccc1C(=O)N" --charge 0 --resname LIG
#
#   # 从现有文件（如 lig.pdb 或 lig.mol2）生成 hiv.mol2
#   bash my_scripts/generate_hiv_mol2_wsl.sh --input lig.pdb --charge 0 --resname LIG

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "[ERR] 缺少依赖：$1" >&2; exit 1; }
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

usage() {
  sed -n '/^# 用法/,/^need_cmd/p' "$0" | sed 's/^# \{0,1\}//'
}

INPUT=""
SMILES=""
RESNAME="LIG"
CHARGE="0"
OUT="hiv.mol2"
PH="7.4"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)  INPUT="$2"; shift 2;;
    --smiles) SMILES="$2"; shift 2;;
    --resname) RESNAME="$2"; shift 2;;
    --charge) CHARGE="$2"; shift 2;;
    --out)    OUT="$2"; shift 2;;
    --ph)     PH="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "[ERR] 未知参数：$1" >&2; usage; exit 1;;
  esac
done

# 基础依赖：antechamber（来自 ambertools）
need_cmd antechamber

tmpdir=$(mktemp -d)
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

seed_sdf="$tmpdir/seed.sdf"

run_with_timeout() {
  # 用法：run_with_timeout <sec> <cmd...>
  local t="$1"; shift || true
  local started=$(date +%s 2>/dev/null || echo 0)
  log_debug "运行命令（超时${t}s）：$*"
  # stdbuf 防止缓冲导致日志不刷新；timeout 防止长时间卡住
  timeout --preserve-status "$t" stdbuf -oL -eL "$@"
  local rc=$?
  if (( rc != 0 )); then
    log_err "命令失败/超时(rc=$rc)：$*"
    return $rc
  fi
  local ended=$(date +%s 2>/dev/null || echo 0)
  log_debug "命令完成，用时 $((ended-started))s"
}

generate_seed_from_smiles() {
  if ! has_cmd obabel; then
    echo "[ERR] 需要 openbabel 才能从 SMILES 生成3D，请先安装：conda install -c conda-forge openbabel" >&2
    exit 2
  fi
  log_info "由 SMILES 生成3D结构 (pH=$PH)"
  log_debug "obabel 版本：$(obabel -V 2>&1 | tr '\n' ' ')"
  run_with_timeout "$OBABEL_TIMEOUT_SEC" env -u LD_PRELOAD -u LD_LIBRARY_PATH \
    obabel -:"$SMILES" -osdf -O "$seed_sdf" --gen3d -p "$PH" -h -v
  # 校验输出是否非空
  if [[ ! -s "$seed_sdf" ]]; then
    log_err "SMILES 转换后 seed SDF 为空：$seed_sdf"
    exit 2
  fi
}

generate_seed_from_file() {
  local in="$1"
  log_debug "输入文件：$in 大小：$(wc -c <"$in" 2>/dev/null || echo '?') 字节  前几行："
  sed -n '1,10p' "$in" | sed 's/^/[IN ] /'
  if has_cmd obabel; then
    log_info "使用 openbabel 统一转换为3D SDF (pH=$PH)"
    log_debug "which obabel: $(command -v obabel)"
    log_debug "obabel 版本：$(obabel -V 2>&1 | tr '\n' ' ')"
    local ext=${in##*.}
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    run_with_timeout "$OBABEL_TIMEOUT_SEC" env -u LD_PRELOAD -u LD_LIBRARY_PATH \
      obabel -i"$ext" "$in" -osdf -O "$seed_sdf" --gen3d -p "$PH" -h -v
    if [[ ! -s "$seed_sdf" ]]; then
      log_err "openbabel 转换后 seed SDF 为空：$seed_sdf"
      exit 2
    fi
  else
    echo "[WARN] 未检测到 openbabel，尝试直接用 antechamber 处理输入（需文件已含3D坐标）"
    # 直接传给 antechamber（后续用 -fi 自动判定不可靠，这里简单依据扩展名）
    local ext=${in##*.}
    ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
    case "$ext" in
      mol2) seed_sdf="$in";;
      sdf)  seed_sdf="$in";;
      pdb)  seed_sdf="$in";;
      *) echo "[ERR] 无 openbabel 且不支持的输入类型：$ext（建议安装 openbabel）" >&2; exit 3;;
    esac
  fi
}

if [[ -n "$SMILES" ]]; then
  generate_seed_from_smiles
elif [[ -n "$INPUT" ]]; then
  [[ -f "$INPUT" ]] || { echo "[ERR] 输入文件不存在：$INPUT" >&2; exit 1; }
  generate_seed_from_file "$INPUT"
else
  # 无参数时的默认：尝试当前目录 hiv.smi / hiv.sdf / hiv.pdb / hiv.mol2
  if [[ -f hiv.smi ]]; then SMILES=$(cat hiv.smi | head -n1 | awk '{print $1}'); generate_seed_from_smiles; 
  elif [[ -f hiv.sdf ]]; then INPUT=hiv.sdf; generate_seed_from_file "$INPUT";
  elif [[ -f hiv.pdb ]]; then INPUT=hiv.pdb; generate_seed_from_file "$INPUT";
  elif [[ -f hiv.mol2 ]]; then INPUT=hiv.mol2; generate_seed_from_file "$INPUT";
  else
    echo "[ERR] 未提供 --input/--smiles，且目录下无 hiv.smi/sdf/pdb/mol2" >&2
    usage
    exit 1
  fi
fi

log_info "使用 antechamber 生成 Tripos mol2（GAFF2 + BCC电荷）"
log_debug "antechamber 版本：$(antechamber -h 2>&1 | head -n1)"
run_with_timeout 900 antechamber -i "$seed_sdf" -fi sdf \
             -o "$tmpdir/lig.mol2" -fo mol2 \
            -rn "$RESNAME" -at gaff2 -c bcc -nc "$CHARGE" -dr no

# 简单校验：是否存在 SUBSTRUCTURE
if ! grep -q '^@<TRIPOS>SUBSTRUCTURE' "$tmpdir/lig.mol2"; then
  echo "[ERR] 生成的 mol2 缺少 SUBSTRUCTURE 段，可能输入缺少3D或依赖异常。" >&2
  echo "      请确认 openbabel 与 ambertools 安装，并确保已生成3D坐标。" >&2
  exit 4
fi

mv -f "$tmpdir/lig.mol2" "$OUT"
echo "[DONE] 已生成：$OUT"
echo "       残基名：$RESNAME，净电荷：$CHARGE"
echo "       可用于 acpype：acpype -i $OUT -b $RESNAME -o gmx"
log_info "日志已保存：$LOG_FILE"
