#!/usr/bin/env bash
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.
set -euo pipefail

# Installs a recent CMake on WSL (Ubuntu/Debian) using Kitware APT repo
# and configures your shell to avoid Anaconda libcurl conflicts when using cmake.
#
# What it does:
# - Adds Kitware APT repo and installs/updates cmake >= 3.18.4
# - Ensures /usr/bin is preferred in PATH
# - Adds an alias so cmake runs without LD_LIBRARY_PATH (fixes conda libcurl warning)
#
# Usage:
#   bash my_scripts/install_cmake_wsl.sh

MIN_VER="3.18.4"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }
}

ver_ge() {
  # dpkg-compare for Debian/Ubuntu
  dpkg --compare-versions "$1" ge "$2"
}

detect_user_home() {
  if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
    getent passwd "$SUDO_USER" | cut -d: -f6
  else
    printf '%s' "$HOME"
  fi
}

ensure_apt_reqs() {
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends \
    ca-certificates gnupg wget lsb-release software-properties-common
}

add_kitware_repo() {
  local keyring="/usr/share/keyrings/kitware-archive-keyring.gpg"
  if [ ! -f "$keyring" ]; then
    echo "Adding Kitware APT key..."
    wget -qO- https://apt.kitware.com/keys/kitware-archive-latest.asc \
      | gpg --dearmor \
      | sudo tee "$keyring" >/dev/null
  fi

  # Detect codename from /etc/os-release or lsb_release
  local codename
  codename=$(. /etc/os-release 2>/dev/null; echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}") || true
  if [ -z "$codename" ] && command -v lsb_release >/dev/null 2>&1; then
    codename$(lsb_release -cs)
  fi
  if [ -z "$codename" ]; then
    echo "Could not detect Ubuntu/Debian codename. Aborting." >&2
    exit 1
  fi

  local list_file="/etc/apt/sources.list.d/kitware.list"
  if ! grep -qs "apt.kitware.com" "$list_file" 2>/dev/null; then
    echo "Adding Kitware APT repo for $codename..."
    echo "deb [signed-by=$keyring] https://apt.kitware.com/ubuntu/ $codename main" \
      | sudo tee "$list_file" >/dev/null
  fi
  sudo apt-get update -y
}

install_cmake() {
  echo "Installing/Updating CMake from Kitware APT..."
  sudo apt-get install -y cmake
}

cmake_version() {
  cmake --version 2>/dev/null | head -n1 | awk '{print $3}'
}

configure_shell() {
  local user_home rc
  user_home="$(detect_user_home)"
  rc="$user_home/.bashrc"

  mkdir -p "$user_home"
  touch "$rc"

  if ! grep -q "cmake-wsl" "$rc" 2>/dev/null; then
    {
      echo ""
      echo "# >>> cmake-wsl >>>"
      echo "# Prefer system binaries (ensure /usr/bin precedes conda)"
      echo "export PATH=/usr/local/bin:/usr/bin:\$PATH"
      echo "# Avoid conda libcurl conflict warning when running cmake"
      echo "alias cmake='env -u LD_LIBRARY_PATH /usr/bin/cmake'"
      echo "# <<< cmake-wsl <<<"
    } >> "$rc"
    echo "Updated $rc with PATH preference and cmake alias."
  else
    echo "$rc already contains cmake-wsl block; leaving as-is."
  fi

  # zsh users: mirror the same block if .zshrc exists and doesn't have it yet
  if [ -f "$user_home/.zshrc" ] && ! grep -q "cmake-wsl" "$user_home/.zshrc" 2>/dev/null; then
    {
      echo ""
      echo "# >>> cmake-wsl >>>"
      echo "export PATH=/usr/local/bin:/usr/bin:\$PATH"
      echo "alias cmake='env -u LD_LIBRARY_PATH /usr/bin/cmake'"
      echo "# <<< cmake-wsl <<<"
    } >> "$user_home/.zshrc"
    echo "Updated $user_home/.zshrc as well."
  fi
}

main() {
  need_cmd sudo
  need_cmd apt-get
  need_cmd dpkg
  need_cmd gpg
  need_cmd wget

  ensure_apt_reqs
  add_kitware_repo
  install_cmake

  local ver
  ver=$(cmake_version || true)
  if [ -z "$ver" ]; then
    echo "CMake did not install correctly." >&2
    exit 1
  fi
  if ver_ge "$ver" "$MIN_VER"; then
    echo "CMake $ver installed (>= $MIN_VER)."
  else
    echo "Warning: CMake $ver < $MIN_VER. Consider upgrading your distro codename or installing from binaries." >&2
  fi

  configure_shell

  echo
  echo "Done. Open a new shell or run:"
  echo "  source ~/.bashrc"
  echo
  echo "Verify with:"
  echo "  cmake --version"
  echo
  echo "If you still see 'libcurl.so.4: no version information' from cmake,"
  echo "make sure you're using the aliased cmake (new shell) or call /usr/bin/cmake explicitly:"
  echo "  env -u LD_LIBRARY_PATH /usr/bin/cmake --version"
}

main "$@"
