<#
SPDX-License-Identifier: GPL-3.0-only
Copyright (C) 2010- The GROMACS Authors
Copyright (C) 2025 GaoZheng

本程序为自由软件：您可以依据自由软件基金会发布的 GNU 通用公共许可证第 3 版（或更高版本）重新分发和/或修改之。
本程序按“现状”提供，不提供任何形式的担保，亦不对适销性或特定用途适用性作出默示担保。详情见 <https://www.gnu.org/licenses/>。

非官方声明：本仓库为 GROMACS 的非官方派生版本，与上游无隶属或担保关系。
#>

param(
    [string]$Destination,
    [string]$RepoUrl,
    [string]$Ref = "HEAD",
    [switch]$Zip,
    [switch]$KeepGit,
    [switch]$NoReadOnly,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info([string]$msg) { Write-Host "[info] $msg" -ForegroundColor Cyan }
function Write-Warn([string]$msg) { Write-Host "[warn] $msg" -ForegroundColor Yellow }
function Write-Err([string]$msg)  { Write-Host "[err ] $msg" -ForegroundColor Red }

function Test-Cmd {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Ensure-Dir {
    param([Parameter(Mandatory)][string]$Path,[switch]$Force)
    if (Test-Path -LiteralPath $Path) {
        if ($Force) {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        } else {
            if (-not (Get-ChildItem -LiteralPath $Path -Force | Select-Object -First 1)) {
                # exists but empty
            } else {
                throw "Destination exists and not empty: $Path (use -Force to overwrite)"
            }
        }
    }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
}

function Set-ReadOnlyRecursive {
    param([Parameter(Mandatory)][string]$Path)
    try {
        # Apply to all files/dirs under destination
        & attrib +R (Join-Path $Path '*') /S /D | Out-Null
        # If a .git exists (e.g., sparse-clone path with -KeepGit), remove read-only on it
        $gitDir = Join-Path $Path '.git'
        if (Test-Path -LiteralPath $gitDir) {
            & attrib -R (Join-Path $gitDir '*') /S /D | Out-Null
        }
    } catch {
        Write-Warn "Failed to set read-only attributes: $($_.Exception.Message)"
    }
}

# 需要导出的路径（相对于仓库根目录）
$IncludePaths = @(
    '.githooks',
    '.vscode',
    'my_docs',
    'my_project',
    'my_scripts',
    'scripts/compliance',
    'LICENSE',
    'README.md'
)

# 解析默认目标目录名
if (-not $Destination -or $Destination.Trim() -eq '') {
    $cwdName = Split-Path -Path (Get-Location) -Leaf
    $Destination = Join-Path (Get-Location) ("{0}_subset_readonly" -f $cwdName)
}

Write-Info "Destination: $Destination"
Ensure-Dir -Path $Destination -Force:$Force

if (-not (Test-Cmd git)) { throw 'git 未安装，无法继续。请先安装 Git。' }

# 优先使用 git archive（本地或远程），失败则回退到稀疏检出
function Try-Export-With-Archive {
    param(
        [string]$RepoUrl,
        [string]$Ref,
        [string]$Destination,
        [string[]]$IncludePaths,
        [switch]$Zip
    )

    $useLocal = -not $RepoUrl -or $RepoUrl.Trim() -eq ''
    $tmpExt = $Zip.IsPresent ? 'zip' : 'tar'
    $tmpPath = Join-Path ([System.IO.Path]::GetTempPath()) ("partial_export_" + [Guid]::NewGuid().ToString() + "." + $tmpExt)

    try {
        if ($useLocal) {
            Write-Info "使用本地仓库 git archive 导出..."
            Push-Location -Path (Get-Location)
            try {
                $args = @('archive')
                if ($Zip) { $args += @('--format=zip','-o',$tmpPath) } else { $args += @('--format=tar','-o',$tmpPath) }
                $args += @($Ref)
                $args += $IncludePaths
                & git @args | Out-Null
            } finally {
                Pop-Location
            }
        } else {
            Write-Info "使用远程仓库 git archive 导出..."
            $args = @('archive')
            if ($Zip) { $args += @('--format=zip','--remote', $RepoUrl, '-o', $tmpPath) } else { $args += @('--format=tar','--remote', $RepoUrl, '-o', $tmpPath) }
            $args += @($Ref)
            $args += $IncludePaths
            & git @args | Out-Null
        }

        if ($Zip) {
            if (-not (Test-Cmd Expand-Archive)) {
                throw '当前 PowerShell 不支持 Expand-Archive，无法解压 zip。请改用 -Zip:$false（tar 模式）。'
            }
            Write-Info "解压 zip 到目标目录..."
            Expand-Archive -Path $tmpPath -DestinationPath $Destination -Force
        } else {
            if (-not (Test-Cmd tar)) {
                throw '系统无 tar 可用，无法解压 tar。请改用 -Zip 开关使用 zip 解压。'
            }
            Write-Info "解压 tar 到目标目录..."
            & tar -xf $tmpPath -C $Destination
        }

        Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue | Out-Null
        return $true
    } catch {
        Write-Warn "git archive 导出失败：$($_.Exception.Message)"
        try { if (Test-Path -LiteralPath $tmpPath) { Remove-Item -LiteralPath $tmpPath -Force -ErrorAction SilentlyContinue | Out-Null } } catch {}
        return $false
    }
}

function Export-With-SparseClone {
    param(
        [Parameter(Mandatory)][string]$RepoUrl,
        [Parameter(Mandatory)][string]$Ref,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)][string[]]$IncludePaths,
        [switch]$KeepGit
    )

    Write-Info "使用 sparse-checkout 回退方案..."
    # 稀疏克隆（浅克隆 + 过滤 blob）
    & git clone --depth 1 --filter=blob:none --sparse $RepoUrl $Destination | Out-Null

    # 进入目标目录，初始化非锥模式以支持精确文件匹配（LICENSE/README.md）
    & git -C $Destination sparse-checkout init --no-cone | Out-Null

    # 将目录规范化为以 '/' 结尾（gitignore 语义），单文件保持原样
    $patterns = @()
    foreach ($p in $IncludePaths) {
        if ($p.EndsWith('/') -or $p.EndsWith('\')) {
            $patterns += ( $p.TrimEnd('/','\') + '/' )
        } elseif ($p -match '\\' ) {
            $patterns += ($p -replace '\\','/') + (if ($p -match '\\$') {'/'} else {''})
            if ($p -match '\\$') { $patterns[-1] = $patterns[-1].TrimEnd('/') + '/' }
        } elseif ($p -match '/') {
            # 包含子路径，可能是目录
            # 尝试作为目录（加 /），但若为文件亦可被匹配
            $patterns += ( $p )
            if (-not $p.EndsWith('/')) { $patterns += ($p.TrimEnd('/') + '/') }
        } else {
            # 根级条目，可能是文件
            if ($p -match '\.' ) { $patterns += ('/' + $p) } else { $patterns += ('/' + $p + '/') }
        }
    }

    # 设置稀疏包含
    & git -C $Destination sparse-checkout set @patterns | Out-Null

    if ($Ref -and $Ref -ne 'HEAD') {
        & git -C $Destination fetch --depth 1 origin $Ref | Out-Null
        & git -C $Destination checkout $Ref | Out-Null
    }

    if (-not $KeepGit) {
        # 移除 .git 以形成不可写的快照（后续会加只读属性）
        $gitDir = Join-Path $Destination '.git'
        if (Test-Path -LiteralPath $gitDir) {
            Remove-Item -LiteralPath $gitDir -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
}

# 主流程
$ok = Try-Export-With-Archive -RepoUrl $RepoUrl -Ref $Ref -Destination $Destination -IncludePaths $IncludePaths -Zip:$Zip
if (-not $ok) {
    if (-not $RepoUrl) {
        # 本地 archive 失败但未提供 RepoUrl，尝试从当前仓库读取 origin
        try {
            $RepoUrl = (git config --get remote.origin.url).Trim()
        } catch {}
    }
    if (-not $RepoUrl) { throw '无法回退到稀疏检出：未提供 RepoUrl，且本地 git archive 失败。' }
    Export-With-SparseClone -RepoUrl $RepoUrl -Ref $Ref -Destination $Destination -IncludePaths $IncludePaths -KeepGit:$KeepGit
}

if (-not $NoReadOnly) {
    Write-Info "设置目标内容为只读..."
    Set-ReadOnlyRecursive -Path $Destination
}

Write-Host "完成：已生成只读的部分克隆快照 → $Destination" -ForegroundColor Green

# 使用说明（简要）：
# 1) 在仓库根目录直接运行（基于本地仓库导出）：
#    pwsh ./Get-ReadonlyPartialClone.ps1
#    可选参数：-Destination 'D:\tmp\subset' -Ref 'v1.0.0' -Zip
# 2) 远程导出（无需本地完整仓库）：
#    pwsh ./Get-ReadonlyPartialClone.ps1 -RepoUrl 'https://github.com/you/yourrepo.git' -Ref main -Destination 'D:\tmp\subset'
# 3) 若 git archive 受限，将自动回退到稀疏克隆；保留 .git 可加 -KeepGit
# 4) 若不希望设置只读属性，可加 -NoReadOnly；覆盖已有目标目录请加 -Force

