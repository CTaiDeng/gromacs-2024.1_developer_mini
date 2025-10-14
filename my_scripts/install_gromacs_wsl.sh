#!/usr/bin/env bash
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.
# Install GROMACS inside WSL (Ubuntu)
# - Supports apt quick install, or source build (default, 2024.1)
# - Installs required build deps and configures environment

set -euo pipefail

METHOD="source"       # source|apt
VERSION="2024.1"
PREFIX="$HOME/gromacs-${VERSION}"
JOBS="$(nproc)"
MPI=0                  # 1 to enable OpenMPI build
SIMD="auto"           # auto|AVX2_256|AVX512|SSE2|…

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --method <source|apt>     Install via Ubuntu apt or build from source (default: source)
  --version <ver>           GROMACS version when source-building (default: ${VERSION})
  --prefix <path>           Install prefix for source build (default: ${PREFIX})
  -j, --jobs <N>            Parallel build jobs (default: nproc)
  --mpi                     Enable MPI build (installs libopenmpi-dev)
  --simd <auto|AVX2_256|...> Set GMX_SIMD (default: auto)
  -h, --help                Show this help

Examples:
  # Quick apt install (system version)
  $(basename "$0") --method apt

  # Build 2024.1 from source (single-precision, OpenMP, no MPI)
  $(basename "$0") --method source --version 2024.1 --prefix ~/gromacs-2024.1 -j 8
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --method) METHOD="$2"; shift 2;;
    --version) VERSION="$2"; shift 2;;
    --prefix) PREFIX="$2"; shift 2;;
    -j|--jobs) JOBS="$2"; shift 2;;
    --mpi) MPI=1; shift;;
    --simd) SIMD="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

# Sanity: WSL + Ubuntu
if ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "[WARN] Not detected as WSL. Continuing anyway..."
fi
if ! grep -qiE 'ubuntu|debian' /etc/os-release 2>/dev/null; then
  echo "[WARN] Not an Ubuntu/Debian base. Script may fail."
fi

sudo_apt() { sudo DEBIAN_FRONTEND=noninteractive apt-get -y "$@"; }

install_apt() {
  echo "[INFO] Installing gromacs via apt"
  sudo_apt update
  sudo_apt install gromacs gromacs-data
  echo "[DONE] Run 'gmx --version' to verify."
}

download_or_use_local() {
  local ver="$1"
  local out_tar="$2"
  # Prefer a local tarball from repo if present
  local script_dir; script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
  local local_tar="${script_dir}/../res/gromacs-${ver}.tar.gz"
  if [[ -f "$local_tar" ]]; then
    echo "[INFO] Using local tarball: $local_tar"
    cp -f "$local_tar" "$out_tar"
    return 0
  fi
  # Download from official site
  local url="https://ftp.gromacs.org/gromacs/gromacs-${ver}.tar.gz"
  echo "[INFO] Downloading: $url"
  curl -fL --retry 3 -o "$out_tar" "$url"
}

install_source() {
  echo "[INFO] Installing build dependencies"
  sudo_apt update
  pkgs=(build-essential cmake git curl libfftw3-dev)
  if [[ $MPI -eq 1 ]]; then pkgs+=(libopenmpi-dev openmpi-bin); fi
  sudo_apt install "${pkgs[@]}"

  mkdir -p "$HOME/src" && cd "$HOME/src"
  local tar="gromacs-${VERSION}.tar.gz"
  if [[ ! -f "$tar" ]]; then
    download_or_use_local "$VERSION" "$tar"
  fi
  rm -rf "gromacs-${VERSION}" && tar -xzf "$tar"
  cd "gromacs-${VERSION}"
  rm -rf build && mkdir build && cd build

  echo "[INFO] Configuring CMake"
  cmake_opts=(
    -DCMAKE_INSTALL_PREFIX="${PREFIX}"
    -DGMX_BUILD_OWN_FFTW=OFF
    -DGMX_DOUBLE=OFF
    -DGMX_MPI=$([[ $MPI -eq 1 ]] && echo ON || echo OFF)
    -DGMX_OPENMP=ON
    -DGMX_GPU=OFF
    -DREGRESSIONTEST_DOWNLOAD=OFF
  )
  if [[ "$SIMD" != "auto" ]]; then
    cmake_opts+=( -DGMX_SIMD="${SIMD}" )
  fi
  cmake .. "${cmake_opts[@]}"

  echo "[INFO] Building with -j${JOBS}"
  cmake --build . -j"${JOBS}"

  echo "[INFO] Installing to ${PREFIX}"
  cmake --install .

  echo "[INFO] 配置环境变量到 ~/.bashrc（使用固定路径）"
  if ! grep -Fq "/home/coder/src/gromacs-2024.1/build/bin" "$HOME/.bashrc" 2>/dev/null; then
    {
      echo "# GROMACS 2024.1"
      echo "export PATH=/home/coder/src/gromacs-2024.1/build/bin:\$PATH"
    } >> "$HOME/.bashrc"
  fi
  echo "[DONE] 已写入 PATH 到 ~/.bashrc。请重新打开终端或执行: source ~/.bashrc"
}

case "$METHOD" in
  apt) install_apt ;;
  source) install_source ;;
  *) echo "Unknown method: $METHOD" >&2; usage; exit 1;;
esac
