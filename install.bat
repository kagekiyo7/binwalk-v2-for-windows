@echo off
rem ----------------------------------------------------------------------
rem  Installs binwalk (7-Zip based build) into the current Python.
rem  After this, "binwalk" (or "py -3 -m binwalk") can be used anywhere.
rem ----------------------------------------------------------------------
setlocal EnableExtensions
cd /d "%~dp0"

set "PYCMD="
where py >nul 2>nul
if not errorlevel 1 set "PYCMD=py -3"
if not defined PYCMD (
    where python >nul 2>nul
    if not errorlevel 1 set "PYCMD=python"
)
if not defined PYCMD goto :nopython

%PYCMD% -c "import sys; raise SystemExit(0 if sys.version_info >= (3, 8) else 1)"
if errorlevel 1 goto :nopython

if not exist "%~dp0src\binwalk\7-Zip\7z.exe" (
    echo [ERROR] src\binwalk\7-Zip\7z.exe is missing. 1>&2
    echo         Put the contents of 7z2603.zip into src\binwalk\7-Zip\ and run again. 1>&2
    exit /b 1
)
if not exist "%~dp0src\binwalk\7-Zip\7z.dll" (
    echo [ERROR] src\binwalk\7-Zip\7z.dll is missing. 1>&2
    exit /b 1
)

echo.
echo === Installing binwalk ===
%PYCMD% -m pip install --upgrade --force-reinstall "%~dp0."
if errorlevel 1 (
    echo.
    echo pip failed. Retrying without build isolation, for offline use ...
    %PYCMD% -m pip install --force-reinstall --no-build-isolation "%~dp0."
    if errorlevel 1 (
        echo.
        echo [ERROR] Installation failed. Try:  %PYCMD% -m pip install --upgrade pip setuptools wheel
        exit /b 1
    )
)

echo.
echo === Self test ===
pushd "%TEMP%"
%PYCMD% "%~dp0selftest.py"
set "RC=%errorlevel%"
popd
if not "%RC%"=="0" (
    echo.
    echo [ERROR] The self test failed. See the messages above.
    exit /b 1
)

echo.
echo Done. Usage examples:
echo     binwalk firmware.bin
echo     binwalk -eM firmware.bin
echo If "binwalk" is not found, open a new terminal, or use:  %PYCMD% -m binwalk firmware.bin
exit /b 0

:nopython
echo [ERROR] Python 3.8 or later was not found. 1>&2
echo         Install it from https://www.python.org/downloads/windows/ 1>&2
echo         and tick "Add python.exe to PATH" in the installer. 1>&2
exit /b 1
