#!/usr/bin/env bash
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.
set -Eeuo pipefail

# 在 WSL(Ubuntu/Debian) 安装 Open Babel（提供 obabel 命令）
# 用法：
#   bash my_scripts/install_openbabel_wsl.sh
# 选项/环境变量：
#   DEBUG=1                 打印调试信息
#   APT_MIRROR=<url>        可选，替换 apt 镜像源（例如：https://mirrors.aliyun.com/ubuntu/）

: "${DEBUG:=1}"
log_info()  { printf "[INFO] %s\n" "$*"; }
log_warn()  { printf "[WARN] %s\n" "$*"; }
log_err()   { printf "[ERR ] %s\n"  "$*" 1>&2; }
log_debug() { [[ "$DEBUG" = 1 ]] && printf "[DBG ] %s\n" "$*"; true; }

if [[ "$DEBUG" = 1 ]]; then
  export PS4='[TRACE] ${BASH_SOURCE##*/}:${LINENO} '
  set -x
fi

if ! grep -qi microsoft /proc/version 2>/dev/null; then
  log_warn "未检测到 WSL 特征，继续按 Debian/Ubuntu 处理"
fi

if ! command -v apt-get >/dev/null 2>&1; then
  log_err "未找到 apt-get。请在 Debian/Ubuntu/WSL 上运行。"
  exit 1
fi

# 可选：切换 apt 镜像
if [[ -n "${APT_MIRROR-}" ]]; then
  log_info "使用自定义 apt 镜像：$APT_MIRROR"
  sudo sed -i "s#http[s\?]*://[^ ]\+#$APT_MIRROR#g" /etc/apt/sources.list
fi

log_info "更新包索引"
sudo apt-get update -y

log_info "安装 Open Babel（obabel）"
sudo apt-get install -y --no-install-recommends \
  ca-certificates gnupg \
  openbabel openbabel-data

log_info "验证安装"
if ! command -v obabel >/dev/null 2>&1; then
  log_err "obabel 未找到。请检查 apt 输出或尝试 conda 安装：conda install -c conda-forge openbabel"
  exit 2
fi

obabel -V
log_info "Open Babel 安装完成"
