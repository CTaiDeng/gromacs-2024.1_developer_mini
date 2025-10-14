REM Copyright (C) 2025 GaoZheng
REM SPDX-License-Identifier: GPL-3.0-only
REM This file is part of this project.
REM Licensed under the GNU General Public License version 3.
REM See https://www.gnu.org/licenses/gpl-3.0.html for details.
@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem -------------------------------------------------
rem Setup Python virtualenv and install project deps
rem Default: envdir=.venv, install numpy; torch (CPU) optional
rem Flags:
rem   --envdir <dir>           Target virtualenv directory (default .venv)
rem   --requirements <path>    Install from requirements.txt first (optional)
rem   --no-torch               Do not install PyTorch (CPU)
rem   --tests                  Also install pytest (optional)
rem   --trace                  Print commands before running
rem   --install-hooks          Install repo git hooks (pre-commit, commit-msg)
rem -------------------------------------------------

set "ENVDIR=.venv"
set "REQUIREMENTS="
set "INSTALL_TORCH=1"
set "INSTALL_TESTS=0"
set "TRACE=0"
set "INSTALL_HOOKS=0"

:prepare_env
rem Avoid permission issues with global pip cache
set "PIP_CACHE_DIR=%CD%\.pip-cache"
if not exist "%PIP_CACHE_DIR%" mkdir "%PIP_CACHE_DIR%" >NUL 2>&1
set "PIP_DISABLE_PIP_VERSION_CHECK=1"

:parse_args
if "%~1"=="" goto args_done
if /I "%~1"=="--envdir" (
  set "ENVDIR=%~2"
  shift & shift & goto parse_args
)
if /I "%~1"=="--requirements" (
  set "REQUIREMENTS=%~2"
  shift & shift & goto parse_args
)
if /I "%~1"=="--no-torch" (
  set "INSTALL_TORCH=0"
  shift & goto parse_args
)
if /I "%~1"=="--tests" (
  set "INSTALL_TESTS=1"
  shift & goto parse_args
)
if /I "%~1"=="--trace" (
  set "TRACE=1"
  shift & goto parse_args
)
if /I "%~1"=="--install-hooks" (
  set "INSTALL_HOOKS=1"
  shift & goto parse_args
)

echo Unknown argument: %~1
exit /b 1

:args_done

if "%TRACE%"=="1" echo [debug] trace enabled

rem Resolve Python (prefer py -3, then python)
set "PY_CMD="
py -3 -c "import sys" >NUL 2>&1 && set "PY_CMD=py -3"
if not defined PY_CMD python -c "import sys" >NUL 2>&1 && set "PY_CMD=python"
if not defined PY_CMD (
  echo [error] Python 3.8+ not found. Please install Python or the Windows Python Launcher.
  exit /b 1
)

if "%TRACE%"=="1" echo [exec] %PY_CMD% -m venv "%ENVDIR%"
%PY_CMD% -m venv "%ENVDIR%"
if errorlevel 1 goto error

set "VENVPY=%ENVDIR%\Scripts\python.exe"
if not exist "%VENVPY%" (
  echo [error] virtualenv python not found: "%VENVPY%"
  goto error
)

call :run "%VENVPY%" -m pip install --no-cache-dir --upgrade pip setuptools wheel || goto error

if defined REQUIREMENTS (
  if "%TRACE%"=="1" echo [info] installing from requirements: "%REQUIREMENTS%"
  call :run "%VENVPY%" -m pip install --no-cache-dir --upgrade -r "%REQUIREMENTS%" || goto error
)

rem Project-required: numpy
call :run "%VENVPY%" -m pip install --no-cache-dir --upgrade numpy || goto error
"%VENVPY%" -c "import numpy as _; print('numpy ok')" >NUL 2>&1
if errorlevel 1 (
  echo [warn] numpy import failed, retrying with binary wheels...
  call :run "%VENVPY%" -m pip install --no-cache-dir --upgrade --only-binary=:all: numpy || goto error
  call :run "%VENVPY%" -c "import numpy as _; print('numpy ok')" || goto error
)

rem Optional: PyTorch (CPU)
if "%INSTALL_TORCH%"=="1" (
  call :run "%VENVPY%" -m pip install --no-cache-dir --upgrade torch --index-url https://download.pytorch.org/whl/cpu
  set "TORCH_STATUS=%ERRORLEVEL%"
) else (
  set "TORCH_STATUS=999"
)

rem Optional: tests
if "%INSTALL_TESTS%"=="1" (
  call :run "%VENVPY%" -m pip install --no-cache-dir --upgrade pytest pytest-cov || goto error
)

rem Optional: Google Generative AI SDK (for AI commit message helper)
call :run "%VENVPY%" -m pip install --no-cache-dir --upgrade google-generativeai
"%VENVPY%" -c "import google.generativeai as _; print('google-generativeai ok')" >NUL 2>&1
if errorlevel 1 (
  echo [warn] google-generativeai not available; skipping verification
)

echo [ok] versions:
call :run "%VENVPY%" -c "import sys,platform; print('Python:', sys.version); import numpy as np; print('numpy:', np.__version__)" || goto error
if "%TORCH_STATUS%"=="0" (
  call :run "%VENVPY%" -c "import torch; print('torch:', torch.__version__, 'cuda:', torch.cuda.is_available())" || echo [warn] torch import failed unexpectedly
) else (
  if "%INSTALL_TORCH%"=="1" echo [warn] torch installation may be unsupported on this Python; skipped reporting
)

echo.
echo [done] Activate your environment:
echo    "%ENVDIR%\Scripts\activate"
echo.
if "%INSTALL_HOOKS%"=="1" (
  echo [info] Installing git hooks ^(pre-commit, commit-msg^)
  if exist "%CD%\script\install-git-hooks.py" (
    "%VENVPY%" "%CD%\script\install-git-hooks.py" --force || goto error
  ) else (
    echo [warn] Hook installer not found under script/
  )
  rem Configure default commit message via commit.template
  if exist "%CD%\script\commit_template.txt" (
    git -C "%CD%" config commit.template script/commit_template.txt >NUL 2>&1
    echo [info] commit.template -> script/commit_template.txt
  )
)
exit /b 0

:run
if "%TRACE%"=="1" echo [exec] %*
%*
exit /b %ERRORLEVEL%

:error
echo [fail] setup failed (errorlevel=%ERRORLEVEL%)
exit /b 1
