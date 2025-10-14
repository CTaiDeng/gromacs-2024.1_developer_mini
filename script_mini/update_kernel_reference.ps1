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

$py = Resolve-Python
& $py $script
exit $LASTEXITCODE

