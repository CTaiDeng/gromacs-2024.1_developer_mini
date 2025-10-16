#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2010- The GROMACS Authors
# Copyright (C) 2025 GaoZheng
#
# 本脚本为自由软件，遵循 GPL-3.0；不提供任何担保。
# 目的：WSL/Ubuntu 下修复 CMake “Could NOT find Python3 (missing: ... Development[.Module|.Embed])”

set -euo pipefail

show_help() {
  cat <<'EOF'
修复 WSL 下 CMake 无法找到 Python3 开发组件（头文件/库）的错误。

用法：
  bash my_scripts/fix_cmake_python3_dev_wsl.sh [--no-apt] [--py 3.X] \
      [--source-dir <SRC>] [--build-dir <BUILD>] [--cmake-args "..."]

选项：
  --no-apt        跳过 apt 安装，仅做 CMake 重新配置
  --py 3.X        指定目标 Python 次版本（例如 3.10）。默认自动检测系统 python3
  --source-dir    源码目录（默认当前目录）
  --build-dir     构建目录（默认 cmake-build-release-wsl）
  --cmake-args    追加传给 CMake 的参数（原样拼接）

说明：
  - CMake 的 FindPython3(… COMPONENTS Development …) 需要 Python 头文件与开发库。
  - 在 Ubuntu/WSL 中安装 python3-dev 及对应版本的 python3.X-dev/libpython3.X-dev 即可。
EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  show_help; exit 0
fi

RUN_APT=1
PYVER_SPEC=""
SRC_DIR="$(pwd)"
BUILD_DIR="cmake-build-release-wsl"
EXTRA_CMAKE_ARGS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-apt) RUN_APT=0; shift;;
    --py) PYVER_SPEC="${2:?}"; shift 2;;
    --source-dir) SRC_DIR="${2:?}"; shift 2;;
    --build-dir) BUILD_DIR="${2:?}"; shift 2;;
    --cmake-args) EXTRA_CMAKE_ARGS="${2:?}"; shift 2;;
    -h|--help) show_help; exit 0;;
    *) echo "[WARN] 未知参数：$1" >&2; shift;;
  esac
done

detected_pyver() {
  if [[ -n "${PYVER_SPEC}" ]]; then
    echo "${PYVER_SPEC}"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
PY
    return 0
  fi
  echo "3" # 极端降级
}

apt_has_pkg() {
  local pkg="$1"
  apt-cache policy "$pkg" >/dev/null 2>&1
}

install_dev_pkgs() {
  if [[ ${RUN_APT} -ne 1 ]]; then
    echo "[INFO] 跳过 apt 安装。"
    return 0
  fi
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "[WARN] 未找到 apt-get，无法自动安装。请手动安装 python3-dev 等。"
    return 0
  fi
  local ver="$1"
  local pkgs=("python3" "python3-pip" "python3-venv" "python3-dev" "pkg-config")
  echo "[INFO] 安装基础包：${pkgs[*]}"
  sudo apt-get update -y
  sudo apt-get install -y "${pkgs[@]}"
  # 尝试安装版本特定的开发包
  local ver_pkg="python${ver}-dev"
  local libver_pkg="libpython${ver}-dev"
  local extra=()
  if apt_has_pkg "$ver_pkg"; then extra+=("$ver_pkg"); fi
  if apt_has_pkg "$libver_pkg"; then extra+=("$libver_pkg"); fi
  if ((${#extra[@]})); then
    echo "[INFO] 安装版本特定开发包：${extra[*]}"
    sudo apt-get install -y "${extra[@]}"
  else
    echo "[INFO] 未发现版本特定包（$ver），跳过。"
  fi
}

rerun_cmake() {
  mkdir -p "${BUILD_DIR}"
  local pyexe
  pyexe="$(command -v python3 || true)"
  local args=("-S" "${SRC_DIR}" "-B" "${BUILD_DIR}" "-DCMAKE_BUILD_TYPE=Release")
  if [[ -n "$pyexe" ]]; then
    args+=("-DPython3_EXECUTABLE=${pyexe}")
  fi
  # 在某些环境里可以帮助定位
  args+=("-DPython3_FIND_STRATEGY=LOCATION" "-DPython3_FIND_IMPLEMENTATIONS=CPython")
  echo "[INFO] 运行 CMake：cmake ${args[*]} ${EXTRA_CMAKE_ARGS}"
  cmake "${args[@]}" ${EXTRA_CMAKE_ARGS}
}

main() {
  local ver
  ver="$(detected_pyver)"
  echo "[INFO] Python3 目标版本：${ver}"
  install_dev_pkgs "$ver"
  echo "[INFO] Python3 头文件路径（若已安装）："
  python3 - <<'PY' || true
import sysconfig
print(sysconfig.get_paths().get('include'))
PY
  rerun_cmake
  echo "[OK] 完成。若仍失败，请手动安装对应的 pythonX.Y-dev 与 libpythonX.Y-dev。"
}

main "$@"

