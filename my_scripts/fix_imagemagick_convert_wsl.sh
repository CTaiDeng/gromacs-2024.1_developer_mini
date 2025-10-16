#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2010- The GROMACS Authors
# Copyright (C) 2025 GaoZheng
#
# 本脚本按 GPL-3.0 授权分发；不提供任何担保。
# 目的：修复 WSL/Ubuntu 下 CMake 使用 ImageMagick convert 报 “not authorized/unauthorized” 的问题。

set -euo pipefail

show_help() {
  cat <<'EOF'
修复 WSL 下 ImageMagick convert 受 policy.xml 限制导致的 “not authorized/unauthorized” 错误。

用法：
  bash my_scripts/fix_imagemagick_convert_wsl.sh [--no-apt] [--restore]

选项：
  --no-apt   不执行 apt 安装，仅进行策略修复/检测（需已安装 imagemagick/ghostscript）
  --restore  恢复 policy.xml 到修复前的备份版本（若存在）

说明：
  - Ubuntu 的 ImageMagick 默认禁用 PDF/PS/EPS/XPS（及 ghostscript 委托）以减少安全风险。
  - CMake 有时需要将示例 PDF/EPS 转为 PNG/JPG 做文档或样例展示，因而会失败。
  - 本脚本按容器构建脚本中的做法，删除 policy.xml 中的相关禁用条目。

EOF
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  show_help
  exit 0
fi

RUN_APT=1
DO_RESTORE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-apt) RUN_APT=0; shift ;;
    --restore) DO_RESTORE=1; shift ;;
    *) echo "[WARN] 未知参数：$1" >&2; shift ;;
  esac
done

if [[ -r /proc/version ]] && grep -qi microsoft /proc/version; then
  echo "[INFO] 检测到 WSL 环境。"
fi

POLICY_CANDIDATES=(
  "/etc/ImageMagick-6/policy.xml"
  "/etc/ImageMagick-7/policy.xml"
  "/etc/ImageMagick/policy.xml"
)

install_pkgs() {
  if [[ ${RUN_APT} -ne 1 ]]; then
    echo "[INFO] 跳过 apt 安装。"
    return 0
  fi
  if command -v apt-get >/dev/null 2>&1; then
    echo "[INFO] 安装 ImageMagick 及 Ghostscript 依赖..."
    sudo apt-get update -y
    sudo apt-get install -y imagemagick ghostscript
  else
    echo "[WARN] 未找到 apt-get，跳过依赖安装。"
  fi
}

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    local bak="${f}.bak.$(date +%Y%m%d%H%M%S)"
    echo "[INFO] 备份 $f -> $bak"
    sudo cp -a "$f" "$bak"
  fi
}

restore_backup_if_present() {
  local f="$1"
  local last_bak
  last_bak=$(ls -1t "${f}.bak."* 2>/dev/null | head -n1 || true)
  if [[ -n "$last_bak" && -f "$last_bak" ]]; then
    echo "[INFO] 恢复 $last_bak -> $f"
    sudo cp -a "$last_bak" "$f"
  else
    echo "[WARN] 找不到可用备份：${f}.bak.*"
  fi
}

patch_policy() {
  local f="$1"
  echo "[INFO] 修补策略文件：$f"
  backup_file "$f"
  # 参考 admin/containers/scripted_gmx_docker_builds.py 的做法
  sudo sed -i '/"XPS"/d; /"PDF"/d; /"PS"/d; /"EPS"/d; /disable ghostscript format types/d' "$f" || true
}

post_check() {
  echo "[INFO] convert 版本："
  if command -v convert >/dev/null 2>&1; then
    convert -version | head -n1 || true
  else
    echo "[WARN] 未找到 convert 命令（imagemagick 未正确安装？）"
  fi
  echo "[INFO] 尝试基本转换测试（生成 1x1 PNG）..."
  if command -v convert >/dev/null 2>&1; then
    convert -size 1x1 xc:white /tmp/ci-im-test.png || true
    if [[ -f /tmp/ci-im-test.png ]]; then
      echo "[OK] 基本转换成功：/tmp/ci-im-test.png"
      rm -f /tmp/ci-im-test.png
    else
      echo "[WARN] 基本转换未成功，请查看 CMake/日志中的错误信息。"
    fi
  fi
}

main() {
  install_pkgs

  local found=0
  for f in "${POLICY_CANDIDATES[@]}"; do
    if [[ -f "$f" ]]; then
      found=1
      if [[ ${DO_RESTORE} -eq 1 ]]; then
        restore_backup_if_present "$f"
      else
        patch_policy "$f"
      fi
    fi
  done

  if [[ $found -eq 0 ]]; then
    echo "[WARN] 未找到 policy.xml（ImageMagick 可能未安装）。"
  fi

  post_check
  echo "[TIP] 若 CMake 仍提示 ImageMagick convert 不可用："
  echo "      - 确认已安装 ghostscript，并且 policy.xml 中未含 PDF/PS/EPS/XPS 禁用条目"
  echo "      - 或跳过该步骤（若构建不需要生成示例图片）"
}

main "$@"

