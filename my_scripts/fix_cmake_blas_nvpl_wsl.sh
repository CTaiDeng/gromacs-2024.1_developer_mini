#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2010- The GROMACS Authors
# Copyright (C) 2025 GaoZheng
#
# 本脚本为自由软件：您可以在 GPL-3.0 许可下重新发布或修改；
# 本脚本按“无任何担保”提供，详情见 https://www.gnu.org/licenses/gpl-3.0.html。

set -euo pipefail

show_help() {
  cat <<'EOF'
修复 WSL 下 CMake 对 NVPL 的查找告警，并配置 BLAS/LAPACK。

用法：
  bash my_scripts/fix_cmake_blas_nvpl_wsl.sh [--mode <openblas|internal|suppress>] \
      [--source-dir <SRC>] [--build-dir <BUILD>] [--no-apt] [--cmake-args "..."]

选项：
  --mode           解决策略（默认 openblas）：
                   - openblas  安装/启用 OpenBLAS，并抑制 NVPL 查找
                   - internal  使用 GROMACS 内置最小 BLAS/LAPACK，并抑制 NVPL 查找
                   - suppress  仅抑制 NVPL 查找（不改变 BLAS 提供商）
  --source-dir     工程源码目录（默认当前仓库根）
  --build-dir      构建目录（默认 cmake-build-release-wsl）
  --no-apt         跳过 apt 安装步骤（离线/最小化环境）
  --cmake-args     追加传递给 CMake 的额外参数（原样拼接）

说明：
  - openblas 模式会优先采用系统 OpenBLAS（需要 libopenblas-dev & liblapack-dev）。
  - internal 模式关闭外部 BLAS/LAPACK 搜索，使用 GROMACS 内置实现。
  - suppress 模式仅添加 -DCMAKE_DISABLE_FIND_PACKAGE_nvpl=ON 来消除告警。

示例：
  # 方案 1（推荐）：安装 OpenBLAS 并配置
  bash my_scripts/fix_cmake_blas_nvpl_wsl.sh --mode openblas

  # 方案 2：不依赖任何外部 BLAS/LAPACK（更省事）
  bash my_scripts/fix_cmake_blas_nvpl_wsl.sh --mode internal

  # 方案 3：仅抑制 NVPL 告警，不改现有策略
  bash my_scripts/fix_cmake_blas_nvpl_wsl.sh --mode suppress
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  show_help
  exit 0
fi

# 参数默认值
MODE="openblas"
SRC_DIR="$(pwd)"
BUILD_DIR="cmake-build-release-wsl"
RUN_APT=1
EXTRA_CMAKE_ARGS=""

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:?}"; shift 2;;
    --source-dir)
      SRC_DIR="${2:?}"; shift 2;;
    --build-dir)
      BUILD_DIR="${2:?}"; shift 2;;
    --no-apt)
      RUN_APT=0; shift;;
    --cmake-args)
      EXTRA_CMAKE_ARGS="${2:?}"; shift 2;;
    -h|--help)
      show_help; exit 0;;
    *)
      echo "[WARN] 未知参数：$1" >&2; shift;;
  esac
done

# 简单 WSL 环境探测（仅提示，不强制）
if [[ -r /proc/version ]] && grep -qi "microsoft" /proc/version; then
  echo "[INFO] 检测到 WSL 环境。"
else
  echo "[INFO] 未检测到 WSL 标识，继续执行（如在原生 Linux 亦可）。"
fi

mkdir -p "${BUILD_DIR}"

apt_install_if_needed() {
  local pkgs=("build-essential" "pkg-config")
  if [[ "${MODE}" == "openblas" ]]; then
    pkgs+=("libopenblas-dev" "liblapack-dev")
  fi
  if command -v apt-get >/dev/null 2>&1; then
    echo "[INFO] 使用 apt-get 安装依赖：${pkgs[*]}"
    sudo apt-get update -y
    sudo apt-get install -y "${pkgs[@]}"
  else
    echo "[WARN] 未找到 apt-get，跳过依赖安装。请自行确保所需库已安装。"
  fi
}

generate_cmake_cmd() {
  local common=("-S" "${SRC_DIR}" "-B" "${BUILD_DIR}" "-DCMAKE_BUILD_TYPE=Release")
  case "${MODE}" in
    openblas)
      printf '%s\n' "cmake ${common[*]} -DBLA_VENDOR=OpenBLAS -DCMAKE_DISABLE_FIND_PACKAGE_nvpl=ON ${EXTRA_CMAKE_ARGS}"
      ;;
    internal)
      printf '%s\n' "cmake ${common[*]} -DGMX_EXTERNAL_BLAS=OFF -DGMX_EXTERNAL_LAPACK=OFF -DCMAKE_DISABLE_FIND_PACKAGE_nvpl=ON ${EXTRA_CMAKE_ARGS}"
      ;;
    suppress)
      printf '%s\n' "cmake ${common[*]} -DCMAKE_DISABLE_FIND_PACKAGE_nvpl=ON ${EXTRA_CMAKE_ARGS}"
      ;;
    *)
      echo "[ERROR] 非法的 --mode 值：${MODE}" >&2; return 1;;
  esac
}

echo "[INFO] 选择的模式：${MODE}"
echo "[INFO] 源码目录：${SRC_DIR}"
echo "[INFO] 构建目录：${BUILD_DIR}"

if [[ ${RUN_APT} -eq 1 ]]; then
  apt_install_if_needed
else
  echo "[INFO] 按要求跳过 apt 安装。"
fi

CMAKE_CMD="$(generate_cmake_cmd)"
echo "[INFO] 运行 CMake：${CMAKE_CMD}"
eval "${CMAKE_CMD}"

echo "[OK] 配置完成。可选执行构建："
echo "     cmake --build ${BUILD_DIR} -j $(nproc 2>/dev/null || echo 4)"
echo "[TIP] 若仍见 NVPL 相关提示，可确认已设置 -DCMAKE_DISABLE_FIND_PACKAGE_nvpl=ON，或改用 --mode internal。"

