@echo off
setlocal enabledelayedexpansion
REM === Always set working directory to script folder ===
cd /d "%~dp0"
REM === Set UTF-8 for Unicode support ===
chcp 65001 >nul
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"

REM === 1) Find Python interpreter ===
set "PY_CMD="
for %%I in (py python python3) do (
    where %%I >nul 2>&1
    if not defined PY_CMD if ERRORLEVEL 0 set "PY_CMD=%%I"
)
if not defined PY_CMD (
    echo [ERROR] Python not found in PATH.
    echo Please install Python and enable 'Add to PATH', or disable App Execution Aliases.
    pause
    goto :EOF
)
echo [INFO] Using Python command: %PY_CMD%

REM === 2) Create virtual environment if not exists ===
if not exist ".venv" (
    echo [INFO] Creating virtual environment...
    %PY_CMD% -m venv .venv
) else (
    echo [INFO] Virtual environment already exists.
)

REM === 3) Activate virtual environment ===
call ".venv\Scripts\activate"
if ERRORLEVEL 1 (
    echo [ERROR] Failed to activate virtual environment.
    pause
    goto :EOF
)

REM === 4) Install dependencies if not already installed ===
set "FLAG=%~dp0.venv\deps_installed.flag"
set "VENV_PYTHON=%~dp0.venv\Scripts\python.exe"

if not exist "%FLAG%" (
    echo [INFO] Installing dependencies from requirements.txt...
    
    REM SỬA LỖI: Gọi pip thông qua python.exe của venv để nâng cấp
    "%VENV_PYTHON%" -m pip install --upgrade pip -q
    
    REM Sử dụng lệnh pip đã được nâng cấp để cài đặt requirements
    "%VENV_PYTHON%" -m pip install -r "%~dp0modules\requirements.txt" -q
    
    echo [INFO] Dependencies installed successfully.
    type NUL > "%FLAG%"
) else (
    echo [INFO] Dependencies already installed.
)

REM === 5) Run main.py ===
echo [INFO] Running main.py...
REM Chạy tool
where pythonw >nul 2>nul
if %errorlevel%==0 (
    start "" pythonw main.py
) else (
    start "" python main.py
)
exit