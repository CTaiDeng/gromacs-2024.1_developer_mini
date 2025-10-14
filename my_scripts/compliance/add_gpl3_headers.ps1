#!/usr/bin/env pwsh
# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2010- The GROMACS Authors
# Copyright (C) 2025 GaoZheng
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, version 3.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
#
# ---
#
# This file is part of a modified version of the GROMACS molecular simulation package.
# For details on the original project, consult https://www.gromacs.org.
#
# To help fund GROMACS development, we humbly ask that you cite
# the research papers on the package. Check out https://www.gromacs.org.

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [string[]]$Paths = @('src','api','include','admin','scripts','tests','python_packaging','my_scripts'),
  [string[]]$Extensions = @(
    '.c','.cc','.cpp','.cxx','.h','.hh','.hpp','.hxx','.cu','.cuh',
    '.py','.sh','.ps1','.psm1','.cmake','.bat','.cmd','.js','.ts',
    '.java','.rs','.go','.m','.mm','.R'
  ),
  [switch]$Recurse = $true,
  [ValidateSet('GPL-3.0-only','GPL-3.0-or-later')]
  [string]$Spdx = 'GPL-3.0-only'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RepoRoot {
  try {
    $gitTop = (git rev-parse --show-toplevel) 2>$null
    if ($LASTEXITCODE -eq 0 -and $gitTop) { return (Resolve-Path $gitTop).Path }
  } catch {}
  # Fallback: this script resides under my_scripts/compliance
  return (Resolve-Path "$PSScriptRoot/../.." ).Path
}

$RepoRoot = Get-RepoRoot
Push-Location $RepoRoot
try {
  # Exclusions (paths relative to repo root, case-insensitive)
  $ExcludePaths = @(
    '.git', '.venv', '.pip-cache', 'cmake-build-release-visual-studio-2022', 'out', 'out/', 'logs',
    'my_docs', 'my_docs/', 'my_project/*/LIG.acpype', 'my_docs/project_docs/kernel_reference',
    'res', 'share', 'out', 'out.txt'
  )

  # Files to never touch (explicit whitelist-exclude)
  $NeverTouch = @(
    'my_docs/project_docs/LICENSE.md',
    'my_project/gmx_split_20250924_011827/docs/LICENSE.md'
  )

  function Should-ExcludePath($rel) {
    $r = $rel.ToLowerInvariant()
    foreach ($p in $ExcludePaths) {
      $pp = $p.ToLowerInvariant()
      if ($pp.EndsWith('/*')) {
        $prefix = $pp.Substring(0, $pp.Length-2)
        if ($r.StartsWith($prefix.TrimEnd('/'))) { return $true }
      }
      if ($r -eq $pp.TrimEnd('/')) { return $true }
      if ($r.StartsWith($pp.TrimEnd('/') + '/')) { return $true }
    }
    foreach ($nt in $NeverTouch) {
      $nt = $nt.ToLowerInvariant()
      if ($r -eq $nt) { return $true }
    }
    return $false
  }

  function Detect-Style($file) {
    $name = [IO.Path]::GetFileName($file)
    $ext = [IO.Path]::GetExtension($file).ToLowerInvariant()
    if ($name -ieq 'CMakeLists.txt') { return '#'}
    switch ($ext) {
      { @('.c','.cc','.cpp','.cxx','.h','.hh','.hpp','.hxx','.cu','.cuh','.java','.js','.ts','.m','.mm') -contains $_ } { return 'block' }
      '.bat' { return 'bat' }
      '.cmd' { return 'bat' }
      default { return '#'}
    }
  }

  function Make-HeaderLines($style) {
    $year = '2025'
    $copyLine = "Copyright (C) $year GaoZheng"
    $spdxLine = "SPDX-License-Identifier: $Spdx"
    $gpl = @(
      $copyLine,
      $spdxLine,
      'This file is part of this project.',
      'Licensed under the GNU General Public License version 3.',
      'See https://www.gnu.org/licenses/gpl-3.0.html for details.'
    )
    switch ($style) {
      'block' {
        $lines = @('/*')
        foreach ($l in $gpl) { $lines += " * $l" }
        $lines += ' */'
        return $lines
      }
      'bat' {
        return ($gpl | ForEach-Object { 'REM ' + $_ })
      }
      default {
        return ($gpl | ForEach-Object { '# ' + $_ })
      }
    }
  }

function Already-HasHeader($text) {
    $head = -join ($text | Select-Object -First 120)
    return ($head -match 'SPDX-License-Identifier:\s*GPL-3\.0' -and $head -match 'GNU\s+General\s+Public\s+License')
}

function Insert-Header($path) {
    $style = Detect-Style $path
    $lines = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
    $crlf = ($lines -match "`r`n")
    $eol = if ($crlf) { "`r`n" } else { "`n" }
    $arr = $lines -split "`r?`n"
    # Consolidation path: detect our SPDX header and legacy GROMACS LGPL header near the top
    $head = -join ($arr | Select-Object -First 200)
    $hasSpdx = ($head -match 'SPDX-License-Identifier:\s*GPL-3\.0')
    $hasGmx = ($head -match 'GROMACS molecular simulation package' -and ($head -match 'Lesser\s+General\s+Public\s+License' -or $head -match 'LGPL'))
    if ($hasSpdx -and $hasGmx) {
      # Parse GROMACS year if present
      $gmxYear = '2010-'
      $m = [regex]::Match($head, 'Copyright\s+(\d{4}-?)\s*The\s+GROMACS\s+Authors')
      if ($m.Success) { $gmxYear = $m.Groups[1].Value }

      # Build consolidated header
      $core = @(
        "SPDX-License-Identifier: $Spdx",
        "",
        "Copyright (C) $gmxYear The GROMACS Authors",
        "Copyright (C) 2025 GaoZheng",
        "",
        "This program is free software: you can redistribute it and/or modify",
        "it under the terms of the GNU General Public License as published by",
        "the Free Software Foundation, version 3.",
        "",
        "This program is distributed in the hope that it will be useful,",
        "but WITHOUT ANY WARRANTY; without even the implied warranty of",
        "MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the",
        "GNU General Public License for more details.",
        "",
        "You should have received a copy of the GNU General Public License",
        "along with this program. If not, see <https://www.gnu.org/licenses/>.",
        "",
        "---",
        "",
        "This file is part of a modified version of the GROMACS molecular simulation package.",
        "For details on the original project, consult https://www.gromacs.org.",
        "",
        "To help fund GROMACS development, we humbly ask that you cite",
        "the research papers on the package. Check out https://www.gromacs.org."
      )
      switch ($style) {
        'block' { $cons = @('/*'); foreach ($l in $core) { $cons += ($(if ($l -ne '') {" * $l"} else {' *'})) }; $cons += ' */' }
        'bat'   { $cons = $core | ForEach-Object { if ($_ -ne '') { 'REM ' + $_ } else { 'REM' } } }
        default { $cons = $core | ForEach-Object { if ($_ -ne '') { '# ' + $_ } else { '#' } } }
      }

      # Determine insertion point preserving shebang/encoding
      $insertAt = 0
      if ($arr.Count -gt 0 -and $arr[0].StartsWith('#!')) { $insertAt = 1 }
      if ($arr.Count -gt $insertAt -and $arr[$insertAt] -match 'coding\s*[:=]\s*utf-?8') { $insertAt += 1 }

      # Remove up to two leading comment blocks/lines after insertAt
      $i = $insertAt
      if ($style -eq 'block') {
        $removed = 0
        while ($i -lt $arr.Count -and $removed -lt 2) {
          if ($arr[$i].TrimStart().StartsWith('/*')) {
            $j = $i
            while ($j -lt $arr.Count -and -not $arr[$j].TrimEnd().EndsWith('*/')) { $j++ }
            $i = $j + 1; $removed++
          } elseif (-not $arr[$i].Trim()) { $i++ } else { break }
        }
      } else {
        while ($i -lt $arr.Count -and (-not $arr[$i].Trim() -or $arr[$i].TrimStart().StartsWith('#') -or $arr[$i].TrimStart().StartsWith('REM'))) { $i++ }
      }

      $new = @()
      if ($insertAt -gt 0) { $new += $arr[0..($insertAt-1)] }
      $new += $cons
      if ($i -lt $arr.Count -and $arr[$i].Trim()) { $new += '' }
      $new += $arr[$i..($arr.Count-1)]
      $content = ($new -join $eol)
      if (-not $content.EndsWith($eol)) { $content += $eol }
      Set-Content -LiteralPath $path -Value $content -Encoding utf8
      return $true
    }

    # If header already present, still normalize GaoZheng year formatting (2025- -> 2025)
    if (Already-HasHeader $arr) {
      if ($head -match 'Copyright \(C\) 2025-\s+GaoZheng') {
        $contentFixed = ($lines -replace 'Copyright \(C\) 2025-\s+GaoZheng','Copyright (C) 2025 GaoZheng')
        Set-Content -LiteralPath $path -Value $contentFixed -Encoding utf8
        return $true
      }
      return $false
    }

    $header = Make-HeaderLines $style
    $insertAt = 0
    # Preserve shebang and python encoding line
    if ($arr.Count -gt 0 -and $arr[0].StartsWith('#!')) { $insertAt = 1 }
    if ($arr.Count -gt ($insertAt) -and $arr[$insertAt] -match 'coding\s*[:=]\s*utf-?8') { $insertAt += 1 }

    $before = $arr[0..($insertAt-1)]
    $after = $arr[$insertAt..($arr.Count-1)]
    $new = @()
    if ($before) { $new += $before }
    $new += $header
    if ($after) { $new += $after }
    $content = ($new -join $eol)
    if (-not $content.EndsWith($eol)) { $content += $eol }
    Set-Content -LiteralPath $path -Value $content -Encoding utf8
    return $true
  }

  $extSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
  foreach ($e in $Extensions) { [void]$extSet.Add($e) }

  $scanned = 0; $updated = 0; $skipped = 0
  foreach ($p in $Paths) {
    $abs = Join-Path $RepoRoot $p
    if (-not (Test-Path $abs)) { continue }
    $files = if ($Recurse) { Get-ChildItem -LiteralPath $abs -Recurse -File -ErrorAction SilentlyContinue } else { Get-ChildItem -LiteralPath $abs -File -ErrorAction SilentlyContinue }
    foreach ($f in $files) {
      $rel = (Resolve-Path -LiteralPath $f.FullName).Path.Substring($RepoRoot.Length).TrimStart('\\','/') -replace '\\','/'
      if (Should-ExcludePath $rel) { $skipped++; continue }
      $ext = [IO.Path]::GetExtension($f.Name)
      if (-not $extSet.Contains($ext)) { $skipped++; continue }
      $scanned++
      if ($PSCmdlet.ShouldProcess($rel, 'Insert GPL-3.0 header')) {
        try {
          if (Insert-Header $f.FullName) { $updated++ }
        } catch {
          Write-Warning "Failed: $rel - $_"
          $skipped++
        }
      }
    }
  }

  Write-Host "[gpl-headers] scanned=$scanned updated=$updated skipped=$skipped"
} finally {
  Pop-Location
}
