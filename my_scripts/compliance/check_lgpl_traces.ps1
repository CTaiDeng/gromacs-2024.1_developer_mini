#!/usr/bin/env pwsh
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.
#
# Scan repository for traces of LGPL-2.1 in code files. Writes a list of
# matching file paths to scripts/lgpl_traces_list.txt by default.

[CmdletBinding()] param(
  [string]$Output,
  [int]$HeadLines = 800
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
  try {
    $top = (git rev-parse --show-toplevel) 2>$null
    if ($LASTEXITCODE -eq 0 -and $top) { return (Resolve-Path $top).Path }
  } catch {}
  # Fallback for my_scripts/compliance location
  return (Resolve-Path "$PSScriptRoot/../.." ).Path
}

$RepoRoot = Get-RepoRoot
Push-Location $RepoRoot
try {
  # Default output path under my_scripts/compliance
  if (-not $PSBoundParameters.ContainsKey('Output') -or [string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $PSScriptRoot 'lgpl_traces_list.txt'
  }
  $absOutput = if ([IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $RepoRoot $Output }

  # Code extensions (same union as header check) and CMakeLists.txt
  $extensions = @(
    '.c','.cc','.cpp','.cxx','.h','.hh','.hpp','.hxx','.cu','.cuh',
    '.py','.sh','.ps1','.psm1','.cmake','.bat','.cmd','.js','.ts',
    '.java','.rs','.go','.m','.mm','.R'
  )
  $extSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach($e in $extensions){ [void]$extSet.Add($e) }

  function Is-Eligible($rel){
    $name = [IO.Path]::GetFileName($rel)
    $ext  = [IO.Path]::GetExtension($rel)
    if ($extSet.Contains($ext)) { return $true }
    if ($name -ieq 'CMakeLists.txt') { return $true }
    return $false
  }

  # Case-insensitive patterns to detect LGPL-2.1 traces
  $patterns = @(
    'SPDX-License-Identifier:\s*LGPL-2\.1(?:-only|-or-later)?',
    'GNU\s+Lesser\s+General\s+Public\s+License[^\n]*2\.1',
    'Lesser\s+General\s+Public\s+License[^\n]*2\.1',
    '\bLGPL\b[^\n]*2\.1',
    'GNU\s+Library\s+General\s+Public\s+License[^\n]*2\.1'
  )
  $regex = [string]::Join('|', $patterns)

  function Has-LgplTrace($path){
    try { $lines = Get-Content -LiteralPath $path -TotalCount $HeadLines -ErrorAction Stop } catch { return $false }
    $head = -join $lines
    return ($head -match $regex -as [bool])
  }

  # Get files tracked/untracked but not ignored
  $all = git -c core.quotepath=false ls-files -co --exclude-standard | ForEach-Object { $_.Trim() } | Where-Object { $_ }

  $hits = New-Object System.Collections.Generic.List[string]
  $total = 0; $eligible = 0
  foreach($rel in $all){
    # Skip this script itself and tool trees to avoid false positives on pattern literals
    if ($rel -like 'scripts/*' -or $rel -like 'my_scripts/*') { continue }
    $full = Join-Path $RepoRoot $rel
    if(-not (Test-Path -LiteralPath $full)){ continue }
    $it = Get-Item -LiteralPath $full -ErrorAction SilentlyContinue
    if(-not $it -or $it.PSIsContainer){ continue }
    $total++
    if(-not (Is-Eligible $rel)){ continue }
    $eligible++
    if(Has-LgplTrace $full){ $hits.Add($rel) | Out-Null }
  }

  Set-Content -LiteralPath $absOutput -Value ($hits | Sort-Object) -Encoding UTF8
  Write-Host ("[lgpl-trace-check] files(total)={0} eligible={1} hits={2} -> {3}" -f $total,$eligible,$hits.Count,$absOutput)
} finally {
  Pop-Location
}
