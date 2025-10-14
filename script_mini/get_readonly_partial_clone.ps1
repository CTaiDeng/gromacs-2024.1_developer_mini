<#
SPDX-License-Identifier: GPL-3.0-only
Copyright (C) 2010- The GROMACS Authors
Copyright (C) 2025 GaoZheng

本脚本用于在仓库根目录执行“只读的部分克隆/同步”。
它会在 out/ 下进行临时稀疏克隆，只检出指定路径；然后与当前仓库根目录下对应路径进行逐一同步（新增/更新/删除），
最后把这些路径设置为只读并清理临时目录。

远端仓库：https://github.com/CTaiDeng/gromacs-2024.1_developer.git
包含路径：
  - .githooks/（含子目录）
  - .vscode/（含子目录）
  - my_docs/（含子目录）
  - my_project/（含子目录）
  - my_scripts/（含子目录）
  - logs/（含子目录）
  - LICENSE
  - README.md
  - AGENTS.md
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg) { Write-Host "[info] $msg" -ForegroundColor Cyan }
function Write-Warn([string]$msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }

# 仓库根目录（脚本位于 script_mini/ 下）
$RepoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $RepoRoot '..')).Path

# 临时稀疏克隆目录
$TmpDir = Join-Path $RepoRoot 'out/readonly_partial_clone'

# 远端与包含路径
$RepoUrl = 'https://github.com/CTaiDeng/gromacs-2024.1_developer.git'
$IncludePaths = @(
    '.githooks',
    '.vscode',
    'my_docs',
    'my_project',
    'my_scripts',
    'logs',
    'LICENSE',
    'README.md',
    'AGENTS.md'
)

# 排除清单：以下相对路径在只读同步时不被远端覆盖或删除（始终以本地版本为准）
$ExcludeFiles = @(
    '.githooks/prepare-commit-msg',
    '.githooks/prepare-commit-msg.bat',
    'my_scripts/gen_commit_msg_googleai.py'
)

function Canonical-Rel([string]$RelPath) {
    if (-not $RelPath) { return '' }
    $p = $RelPath.Replace('/', '\\').TrimStart('\\')
    return $p.ToLowerInvariant()
}

function Is-Excluded([string]$FullPath) {
    $rel = Make-Rel $FullPath
    $relNorm = Canonical-Rel $rel
    foreach ($e in $ExcludeFiles) {
        $eNorm = Canonical-Rel $e
        if ($relNorm -eq $eNorm) { return $true }
    }
    return $false
}

# 从源（临时稀疏克隆目录）中删除被排除的文件，避免进入比对/复制流程
function Remove-Excluded-In-Source([string]$RelRoot) {
    $rootNorm = Canonical-Rel $RelRoot
    foreach ($e in $ExcludeFiles) {
        $eNorm = Canonical-Rel $e
        if ($eNorm.StartsWith($rootNorm)) {
            $srcPath = Join-Path $TmpDir $e
            if (Test-Path -LiteralPath $srcPath) {
                try {
                    Remove-Item -LiteralPath $srcPath -Force -ErrorAction SilentlyContinue
                    # 仅输出仓库相对路径，避免出现临时目录前缀
                    $disp = Canonical-Rel $e
                    Write-Info ("Skip source (excluded): {0}" -f $disp)
                } catch {
                    # 忽略
                }
            }
        }
    }
}

function Ensure-Git() {
    try { git --version | Out-Null } catch { throw '未检测到 git，请先安装并确保在 PATH 中。' }
}

function Remove-IfExists([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Clear-ReadOnly-Target([string]$Rel) {
    $dst = Join-Path $RepoRoot $Rel
    if (-not (Test-Path -LiteralPath $dst)) { return }
    if (Test-Path -LiteralPath $dst -PathType Container) {
        & attrib -R (Join-Path $dst '*') /S /D | Out-Null
        & attrib -R $dst | Out-Null
    } else {
        & attrib -R $dst | Out-Null
    }
}

function Set-ReadOnly-Target([string]$Rel) {
    $dst = Join-Path $RepoRoot $Rel
    if (-not (Test-Path -LiteralPath $dst)) { return }
    if (Test-Path -LiteralPath $dst -PathType Container) {
        & attrib +R (Join-Path $dst '*') /S /D | Out-Null
        & attrib +R $dst | Out-Null
    } else {
        & attrib +R $dst | Out-Null
    }
}

function Files-Differ([string]$SrcFile, [string]$DstFile) {
    if (-not (Test-Path -LiteralPath $DstFile)) { return $true }
    $s = Get-Item -LiteralPath $SrcFile
    $d = Get-Item -LiteralPath $DstFile
    if ($s.Length -ne $d.Length) { return $true }
    try {
        $sh = (Get-FileHash -Algorithm SHA256 -LiteralPath $SrcFile).Hash
        $dh = (Get-FileHash -Algorithm SHA256 -LiteralPath $DstFile).Hash
        return -not ($sh -eq $dh)
    } catch {
        # 回退：无法计算哈希时，保守起见视为不同以强制更新
        return $true
    }
}

function Make-Rel([string]$FullPath) {
    $p = [System.IO.Path]::GetFullPath($FullPath)
    $root = [System.IO.Path]::GetFullPath($RepoRoot)
    if ($p.ToLower().StartsWith($root.ToLower())) { return $p.Substring($root.Length).TrimStart('\\') }
    return $FullPath
}

function Sync-Directory([string]$SrcDir, [string]$DstDir) {
    Ensure-Dir $DstDir
    $srcChildren = @(Get-ChildItem -LiteralPath $SrcDir -Force)
    $dstChildren = @()
    if (Test-Path -LiteralPath $DstDir) { $dstChildren = @(Get-ChildItem -LiteralPath $DstDir -Force) }

    $srcMap = @{}
    foreach ($c in $srcChildren) { $srcMap[$c.Name.ToLower()] = $c }
    $dstMap = @{}
    foreach ($c in $dstChildren) { $dstMap[$c.Name.ToLower()] = $c }

    # 删除多余项（跳过排除文件）
    foreach ($k in $dstMap.Keys) {
        if (-not $srcMap.ContainsKey($k)) {
            $toRemove = $dstMap[$k]
            $excluded = $false
            if (Is-Excluded $toRemove.FullName) { $excluded = $true }
            else {
                # 兜底：按文件名匹配到排除列表（防御路径归一化问题）
                $name = $toRemove.Name.ToLowerInvariant()
                foreach ($e in $ExcludeFiles) {
                    $en = [System.IO.Path]::GetFileName((Canonical-Rel $e)).ToLowerInvariant()
                    if ($en -eq $name) { $excluded = $true; break }
                }
            }
            if ($excluded) {
                Write-Info ("Skip delete (excluded): {0}" -f (Make-Rel $toRemove.FullName))
            } else {
                Remove-Item -LiteralPath $toRemove.FullName -Recurse -Force -ErrorAction SilentlyContinue
                Write-Info ("Deleted: {0}" -f (Make-Rel $toRemove.FullName))
            }
        }
    }

    # 同步新增/更新
    foreach ($k in $srcMap.Keys) {
        $s = $srcMap[$k]
        $dFull = Join-Path $DstDir $s.Name
        if ($s.PSIsContainer) {
            if (Test-Path -LiteralPath $dFull) {
                $dItem = Get-Item -LiteralPath $dFull
                if (-not $dItem.PSIsContainer) {
                    if (Is-Excluded $dFull) {
                        Write-Info ("Skip replace dir (excluded target): {0}" -f (Make-Rel $dFull))
                    } else {
                        Remove-Item -LiteralPath $dFull -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            Sync-Directory $s.FullName $dFull
        } else {
            $excluded = $false
            if (Is-Excluded $dFull) { $excluded = $true }
            else {
                $name = [System.IO.Path]::GetFileName($dFull).ToLowerInvariant()
                foreach ($e in $ExcludeFiles) {
                    $en = [System.IO.Path]::GetFileName((Canonical-Rel $e)).ToLowerInvariant()
                    if ($en -eq $name) { $excluded = $true; break }
                }
            }
            if ($excluded) {
                Write-Info ("Skip update (excluded): {0}" -f (Make-Rel $dFull))
                continue
            }
            if (Test-Path -LiteralPath $dFull) {
                $dItem = Get-Item -LiteralPath $dFull
                if ($dItem.PSIsContainer) {
                    Remove-Item -LiteralPath $dFull -Recurse -Force -ErrorAction SilentlyContinue
                    Copy-Item -LiteralPath $s.FullName -Destination $dFull -Force
                    Write-Info ("Replaced dir->file: {0}" -f (Make-Rel $dFull))
                } else {
                    if (Files-Differ $s.FullName $dFull) {
                        Copy-Item -LiteralPath $s.FullName -Destination $dFull -Force
                        Write-Info ("Updated: {0}" -f (Make-Rel $dFull))
                    }
                }
            } else {
                Ensure-Dir (Split-Path -Parent $dFull)
                Copy-Item -LiteralPath $s.FullName -Destination $dFull -Force
                Write-Info ("Added: {0}" -f (Make-Rel $dFull))
            }
        }
    }
}

function Sync-Path([string]$Rel) {
    $src = Join-Path $TmpDir $Rel
    $dst = Join-Path $RepoRoot $Rel

    # 解除只读，以便更新
    Clear-ReadOnly-Target $Rel

    # 先从源侧剔除排除文件，确保后续不同步
    Remove-Excluded-In-Source $Rel

    if (Test-Path -LiteralPath $src) {
        if (Test-Path -LiteralPath $src -PathType Container) {
            if (Test-Path -LiteralPath $dst) {
                $dItem = Get-Item -LiteralPath $dst
                if (-not $dItem.PSIsContainer) { Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue }
            }
            Sync-Directory $src $dst
        } else {
            $excluded = $false
            if (Is-Excluded $dst) { $excluded = $true }
            else {
                $name = [System.IO.Path]::GetFileName($dst).ToLowerInvariant()
                foreach ($e in $ExcludeFiles) {
                    $en = [System.IO.Path]::GetFileName((Canonical-Rel $e)).ToLowerInvariant()
                    if ($en -eq $name) { $excluded = $true; break }
                }
            }
            if ($excluded) {
                Write-Info ("Skip update (excluded): {0}" -f (Make-Rel $dst))
            } else {
                if (Test-Path -LiteralPath $dst) {
                $dItem = Get-Item -LiteralPath $dst
                if ($dItem.PSIsContainer) { Remove-Item -LiteralPath $dst -Recurse -Force -ErrorAction SilentlyContinue }
                if (Files-Differ $src $dst) {
                    Ensure-Dir (Split-Path -Parent $dst)
                    Copy-Item -LiteralPath $src -Destination $dst -Force
                    Write-Info ("Updated: {0}" -f (Make-Rel $dst))
                }
                } else {
                Ensure-Dir (Split-Path -Parent $dst)
                Copy-Item -LiteralPath $src -Destination $dst -Force
                Write-Info ("Added: {0}" -f (Make-Rel $dst))
                }
            }
        }
    } else {
        # 远端不存在该路径，本地若存在则删除（跳过排除文件）
        if (Test-Path -LiteralPath $dst) {
            if (Test-Path -LiteralPath $dst -PathType Container) {
                $children = Get-ChildItem -LiteralPath $dst -Force -Recurse
                foreach ($c in $children) {
                    if (-not $c.PSIsContainer) {
                        $excluded = $false
                        if (Is-Excluded $c.FullName) { $excluded = $true }
                        else {
                            $name = $c.Name.ToLowerInvariant()
                            foreach ($e in $ExcludeFiles) {
                                $en = [System.IO.Path]::GetFileName((Canonical-Rel $e)).ToLowerInvariant()
                                if ($en -eq $name) { $excluded = $true; break }
                            }
                        }
                        if ($excluded) {
                            Write-Info ("Skip delete (excluded): {0}" -f (Make-Rel $c.FullName))
                        } else {
                            Remove-Item -LiteralPath $c.FullName -Force -ErrorAction SilentlyContinue
                            Write-Info ("Deleted: {0}" -f (Make-Rel $c.FullName))
                        }
                    }
                }
            } else {
                if (Is-Excluded $dst) {
                    Write-Info ("Skip delete (excluded): {0}" -f (Make-Rel $dst))
                } else {
                    Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
                    Write-Info ("Deleted (missing upstream): {0}" -f (Make-Rel $dst))
                }
            }
        } else {
            Write-Warn "Upstream missing path: $Rel (nothing to sync)"
        }
    }
}

function Main() {
    Ensure-Git

    Write-Info "[1/6] 准备临时目录: $TmpDir"
    Ensure-Dir (Join-Path $RepoRoot 'out')
    Remove-IfExists $TmpDir

    Write-Info "[2/6] 稀疏克隆远端..."
    git clone --depth 1 --filter=blob:none --sparse $RepoUrl $TmpDir | Out-Null

    Write-Info "[3/6] 配置 sparse-checkout"
    git -C $TmpDir sparse-checkout init --no-cone | Out-Null
    git -C $TmpDir sparse-checkout set @IncludePaths | Out-Null

    Write-Info "[4/6] 同步到本地（新增/更新/删除）"
    foreach ($p in $IncludePaths) { Sync-Path $p }

    Write-Info "[5/6] 设置为只读"
    foreach ($p in $IncludePaths) { Set-ReadOnly-Target $p }

    Write-Info "[6/6] 清理临时目录"
    Remove-IfExists $TmpDir

    Write-Host '完成：本地已与远端目标保持一致（只读）。' -ForegroundColor Green
}

try { Main } catch { Write-Error $_; exit 1 }
