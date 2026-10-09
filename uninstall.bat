@echo off
setlocal
set "PYCMD="
where py >nul 2>nul
if not errorlevel 1 set "PYCMD=py -3"
if not defined PYCMD (
    where python >nul 2>nul
    if not errorlevel 1 set "PYCMD=python"
)
if not defined PYCMD (
    echo [ERROR] Python was not found. 1>&2
    exit /b 1
)
%PYCMD% -m pip uninstall -y binwalk
exit /b %errorlevel%
