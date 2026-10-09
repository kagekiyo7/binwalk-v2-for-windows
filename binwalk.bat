@echo off
rem ----------------------------------------------------------------------
rem  Portable launcher: runs binwalk straight from this folder.
rem  No installation is required (only Python 3.8+).
rem
rem      binwalk.bat -e firmware.bin
rem      binwalk.bat -eM -C C:\out firmware.bin
rem ----------------------------------------------------------------------
setlocal
set "BW_ROOT=%~dp0"
set "PYTHONPATH=%BW_ROOT%src;%PYTHONPATH%"

set "PYCMD="
where py >nul 2>nul
if not errorlevel 1 set "PYCMD=py -3"
if not defined PYCMD (
    where python >nul 2>nul
    if not errorlevel 1 set "PYCMD=python"
)
if not defined PYCMD (
    echo [ERROR] Python 3.8 or later was not found. 1>&2
    echo         Install it from https://www.python.org/downloads/windows/ 1>&2
    exit /b 1
)

%PYCMD% -m binwalk %*
exit /b %errorlevel%
