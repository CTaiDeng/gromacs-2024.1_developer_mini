# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2010- The GROMACS Authors
# Copyright (C) 2025 GaoZheng
# This file is free software under GPL-3.0; see https://www.gnu.org/licenses/gpl-3.0.html

Param(
)

$ErrorActionPreference = 'Stop'

function Resolve-Python {
    foreach ($cand in @('python3', 'python', 'py')) {
        try {
            $v = & $cand --version 2>$null
            if ($LASTEXITCODE -eq 0) { return $cand }
        } catch {}
    }
    throw '未找到 Python 解释器，请安装 Python 3 并确保其在 PATH 中。'
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $repoRoot '..')
$script = Join-Path $repoRoot 'my_scripts/update_kernel_reference.py'

# 运行前先删除临时输出目录，避免 git clone 报 already exists and is not an empty directory
$tmpOutDir = Join-Path $repoRoot 'out' | Join-Path -ChildPath 'kernel_reference_only'
try {
    if (Test-Path -LiteralPath $tmpOutDir) {
        Write-Host "[预清理] 删除临时目录: $tmpOutDir"
        Remove-Item -LiteralPath $tmpOutDir -Recurse -Force -ErrorAction SilentlyContinue
        # 再次检查与简单等待，处理 Windows 文件占用
        Start-Sleep -Milliseconds 200
        if (Test-Path -LiteralPath $tmpOutDir) {
            Write-Host "[预清理] 再次尝试强制删除..."
            Remove-Item -LiteralPath $tmpOutDir -Recurse -Force -ErrorAction Stop
        }
    }
} catch {
    Write-Warning "预清理临时目录失败：$($_.Exception.Message)；将交由 Python 脚本继续处理。"
}

$py = Resolve-Python
& $py $script
exit $LASTEXITCODE
