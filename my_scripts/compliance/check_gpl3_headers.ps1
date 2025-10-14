#!/usr/bin/env pwsh
# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.
#
# Scan the repository for code files that should have GPL-3.0 headers added
# by my_scripts/add_gpl3_headers.*, and list any missing into
# gpl3_header_missing_list.txt at repo root.

[CmdletBinding()] param(
  [string]$Output,
  [int]$HeadLines = 250
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
  # Default output path to scripts/ if not provided
  if (-not $PSBoundParameters.ContainsKey('Output') -or [string]::IsNullOrWhiteSpace($Output)) {
    $Output = Join-Path $PSScriptRoot 'gpl3_header_missing_list.txt'
  }
  $absOutput = if ([IO.Path]::IsPathRooted($Output)) { $Output } else { Join-Path $RepoRoot $Output }
  # Union of extensions handled by add_gpl3_headers.* (PS1 + PY)
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

  function Has-Gpl3Header($path){
    try { $lines = Get-Content -LiteralPath $path -TotalCount $HeadLines -ErrorAction Stop } catch { return $false }
    $head = -join $lines
    return (
      $head -match 'SPDX-License-Identifier:\s*GPL-3\.0' -and
      $head -match 'GNU\s+General\s+Public\s+License'
    )
  }

  # All repo files that are tracked or untracked and not ignored
  $all = git -c core.quotepath=false ls-files -co --exclude-standard | ForEach-Object { $_.Trim() } | Where-Object { $_ }

  $missing = New-Object System.Collections.Generic.List[string]
  $total = 0; $eligible = 0
  foreach($rel in $all){
    $full = Join-Path $RepoRoot $rel
    if(-not (Test-Path -LiteralPath $full)){ continue }
    $it = Get-Item -LiteralPath $full -ErrorAction SilentlyContinue
    if(-not $it -or $it.PSIsContainer){ continue }
    $total++
    if(-not (Is-Eligible $rel)){ continue }
    $eligible++
    if(-not (Has-Gpl3Header $full)){
      $missing.Add($rel) | Out-Null
    }
  }

  # Write report (plain list of relative file paths)
  Set-Content -LiteralPath $absOutput -Value ($missing | Sort-Object) -Encoding UTF8
  Write-Host ("[gpl3-header-check] files(total)={0} eligible={1} missing={2} -> {3}" -f $total,$eligible,$missing.Count,$absOutput)
} finally {
  Pop-Location
}
