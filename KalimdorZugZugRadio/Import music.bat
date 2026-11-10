@echo off
rem Kalimdor ZugZug Radio - imports your music and podcasts (double-click to run).
rem Extra options can be added after the script name, e.g. --keep-originals
cd /d "%~dp0"

rem Try to actually run Python ("where" also finds the Microsoft Store placeholder).
python --version >nul 2>nul
if not errorlevel 1 goto use_python
py -3 --version >nul 2>nul
if not errorlevel 1 goto use_py

echo Python was not found. Install it from https://www.python.org/downloads/
echo and tick "Add python.exe to PATH" during the installation.
goto done

:use_python
python "tools\import_music.py" %*
goto done

:use_py
py -3 "tools\import_music.py" %*

:done
echo.
pause
