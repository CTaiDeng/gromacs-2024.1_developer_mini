REM Copyright (C) 2025 GaoZheng
REM SPDX-License-Identifier: GPL-3.0-only
REM This file is part of this project.
REM Licensed under the GNU General Public License version 3.
REM See https://www.gnu.org/licenses/gpl-3.0.html for details.
@echo off
setlocal EnableExtensions EnableDelayedExpansion
rem Windows prepare-commit-msg hook
rem Steps:
rem  1) If message empty (after stripping comments) -> write "update"
rem  2) If message == "update" -> try generator
rem  3) If generator fails -> keep "update"

set "MSG_FILE=%~1"
set "COMMIT_SOURCE=%~2"
set "COMMIT_MSG_LANG=zh"

rem Skip for merge/squash
if /I "%COMMIT_SOURCE%"=="merge" exit /b 0
if /I "%COMMIT_SOURCE%"=="squash" exit /b 0

if not defined MSG_FILE exit /b 0

rem Strip comments to temp file
set "TMP1=%TEMP%\pcmsg_%RANDOM%.txt"
if exist "%TMP1%" del /q "%TMP1%" >NUL 2>&1
if exist "%MSG_FILE%" (
  for /f "usebackq tokens=* delims=" %%L in ("%MSG_FILE%") do (
    set "LINE=%%L"
    if not "!LINE:~0,1!"=="#" echo %%L>>"%TMP1%"
  )
) else (
  >"%MSG_FILE%" echo update
)

set "CONTENT="
for /f "usebackq tokens=* delims=" %%L in ("%TMP1%") do (
  set "CONTENT=%%L"
  goto :GOT1
)
:GOT1
set "CONTENT=%CONTENT: =%"

rem Step 1: empty -> write update
if "%CONTENT%"=="" (
  >"%MSG_FILE%" echo update
)

rem Step 2: if update -> try generator
set "TMP2=%TEMP%\pcmsg2_%RANDOM%.txt"
if exist "%TMP2%" del /q "%TMP2%" >NUL 2>&1
for /f "usebackq tokens=* delims=" %%L in ("%MSG_FILE%") do (
  set "LINE=%%L"
  if not "!LINE:~0,1!"=="#" echo %%L>>"%TMP2%"
)

set "CUR="
for /f "usebackq tokens=* delims=" %%L in ("%TMP2%") do (
  set "CUR=%%L"
  goto :CHK
)
:CHK
if /I "%CUR%"=="update" (
  call :RUN_GEN "%MSG_FILE%"
)

if exist "%TMP1%" del /q "%TMP1%" >NUL 2>&1
if exist "%TMP2%" del /q "%TMP2%" >NUL 2>&1
endlocal & exit /b 0

:RUN_GEN
setlocal EnableExtensions EnableDelayedExpansion
set "MSG=%~1"
for /f "usebackq delims=" %%R in (`git rev-parse --show-toplevel 2^>NUL`) do set "REPO_ROOT=%%R"
if not defined REPO_ROOT set "REPO_ROOT=%CD%"

set "PY_CMD="
set "PY_ARGS="

rem Prefer repository local venv Python
if exist "%REPO_ROOT%\.venv\Scripts\python.exe" (
  set "PY_CMD=%REPO_ROOT%\.venv\Scripts\python.exe"
  set "PY_ARGS="
) else (
  where py >NUL 2>&1 && ( set "PY_CMD=py" & set "PY_ARGS=-3" )
  if not defined PY_CMD ( where python3 >NUL 2>&1 && ( set "PY_CMD=python3" & set "PY_ARGS=" ) )
  if not defined PY_CMD ( where python >NUL 2>&1 && ( set "PY_CMD=python" & set "PY_ARGS=" ) )
)

if defined PY_CMD (
  if /I "%COMMIT_MSG_DEBUG%"=="1" (
    "%PY_CMD%" %PY_ARGS% "%REPO_ROOT%\my_scripts\gen_commit_msg_googleai.py" > "%MSG%" 2>&1
  ) else (
    "%PY_CMD%" %PY_ARGS% "%REPO_ROOT%\my_scripts\gen_commit_msg_googleai.py" > "%MSG%" 2>NUL
  )
)

rem After generation, ensure not empty
set "HAS=0"
for /f "usebackq tokens=* delims=" %%Z in ("%MSG%") do (
  set "HAS=1"
  goto :AFTER
)
:AFTER
if "%HAS%"=="0" ( >"%MSG%" echo update )
endlocal & exit /b 0
