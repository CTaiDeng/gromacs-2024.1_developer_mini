#!/usr/bin/env bash
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.
# WSL(Ubuntu) one-shot installer for AmberTools + ACPYPE (conda-forge)
# - Prefers micromamba (no admin), falls back to conda/mamba if present
# - Creates an isolated env and verifies CLI tools

set -euo pipefail

ENV_NAME="amber"
PY_VER="3.11"
CHANNEL="conda-forge"
WITH_OPENBABEL=1

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -n, --name <env>        Conda/Mamba env name (default: amber)
  -p, --python <ver>      Python version (default: 3.11)
  -c, --channel <name>    Conda channel (default: conda-forge)
  --no-openbabel          Do not install openbabel
  -h, --help              Show this help

Result:
  Creates env with: ambertools acpype [openbabel]
  Verifies: antechamber, acpype, obabel (if installed)

Notes:
  - Works without sudo. If curl/tar are missing, install them with:
      sudo apt update && sudo apt install -y curl ca-certificates tar bzip2
  - This script prefers micromamba; if conda/mamba exist, they are used.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name) ENV_NAME="$2"; shift 2;;
    -p|--python) PY_VER="$2"; shift 2;;
    -c|--channel) CHANNEL="$2"; shift 2;;
    --no-openbabel) WITH_OPENBABEL=0; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

echo "[INFO] Target env: $ENV_NAME (Python $PY_VER) via $CHANNEL"

# Detect solver
have() { command -v "$1" >/dev/null 2>&1; }

SOLVER=""
RUN_PREFIX=( )

if have mamba; then
  SOLVER="mamba"
elif have conda; then
  SOLVER="conda"
else
  # Install micromamba locally (no sudo)
  echo "[INFO] conda/mamba not found; installing micromamba to ~/.local/bin"
  mkdir -p "$HOME/.local/bin" "$HOME/.mambarc.d" >/dev/null 2>&1 || true
  if ! have curl; then
    echo "[ERROR] curl not found. Install with: sudo apt update && sudo apt install -y curl ca-certificates" >&2
    exit 2
  fi
  curl -fsSL https://micro.mamba.pm/api/micromamba/linux-64/latest -o /tmp/micromamba.tar.bz2
  tar -xjf /tmp/micromamba.tar.bz2 -C "$HOME/.local/bin" bin/micromamba --strip-components=1
  rm -f /tmp/micromamba.tar.bz2
  export PATH="$HOME/.local/bin:$PATH"
  SOLVER="micromamba"
  # micromamba needs a root prefix; use ~/.micromamba by default
  export MAMBA_ROOT_PREFIX="${HOME}/.micromamba"
  RUN_PREFIX=( micromamba )
fi

echo "[INFO] Using solver: $SOLVER"

create_env() {
  local pkgs=( "python=${PY_VER}" ambertools acpype )
  if [[ $WITH_OPENBABEL -eq 1 ]]; then pkgs+=( openbabel ); fi
  case "$SOLVER" in
    mamba|conda)
      $SOLVER create -y -n "$ENV_NAME" -c "$CHANNEL" "${pkgs[@]}"
      ;;
    micromamba)
      micromamba create -y -n "$ENV_NAME" -c "$CHANNEL" "${pkgs[@]}"
      ;;
  esac
}

install_if_missing() {
  case "$SOLVER" in
    mamba|conda)
      $SOLVER list -n "$ENV_NAME" >/dev/null 2>&1 || create_env
      ;;
    micromamba)
      micromamba env list | grep -q "^$ENV_NAME\>" || create_env
      ;;
  esac
}

install_if_missing

run_in_env() {
  case "$SOLVER" in
    mamba|conda)
      conda run -n "$ENV_NAME" "$@"
      ;;
    micromamba)
      micromamba run -n "$ENV_NAME" "$@"
      ;;
  esac
}

echo "[INFO] Verifying tools in env '$ENV_NAME'"
set +e
run_in_env antechamber -h >/dev/null 2>&1 && echo "  - antechamber OK" || echo "  - antechamber NOT FOUND"
run_in_env acpype -h >/dev/null 2>&1 && echo "  - acpype OK" || echo "  - acpype NOT FOUND"
if [[ $WITH_OPENBABEL -eq 1 ]]; then
  run_in_env obabel -V >/dev/null 2>&1 && echo "  - obabel OK" || echo "  - obabel NOT FOUND"
fi
set -e

cat <<EOT

[DONE] AmberTools + ACPYPE installed in env: $ENV_NAME

To use:
  # Activate (conda/mamba):
  conda activate $ENV_NAME
  # or run without activation:
  conda run -n $ENV_NAME acpype -h

Example ACPYPE usage:
  conda run -n $ENV_NAME acpype -i ligand.mol2 -b LIG -o gmx

EOT
