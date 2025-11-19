@echo off
:: =============================================================================
::  AutoInstall-Python-and-Run.bat
::  Cài Python (nếu thiếu) + tạo venv + cài deps + chạy source\main.py
::  - Console UTF-8 hiển thị tiếng Việt
::  - Tự nâng quyền Admin khi cần (InstallAllUsers)
::  - Phát hiện x64/x86, tải đúng installer từ python.org (có retry, timeout, proxy)
::  - Kiểm SHA256 (tùy chọn), Unblock-File, cảnh báo Pending Reboot
::  - So sánh version: nếu Python hiện có >= PY_MIN_VERSION thì KHÔNG cài
::  - Patch PATH tạm thời để dùng ngay sau cài
::  - Ưu tiên dùng Python Launcher (py) để né App Execution Aliases
::  - Venv: tự tạo, tự sửa chữa nếu hỏng, pip install có retry
::  - Không bỏ bất kỳ khối logic nào đã yêu cầu trước đó
:: =============================================================================

setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

:: ---------------------------
:: Console UTF-8 + biến môi trường UTF-8 cho Python
:: ---------------------------
chcp 65001 >nul
set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"

:: Force pip to install only inside the active virtualenv; ignore user site
set "PIP_REQUIRE_VIRTUALENV=1"
set "PYTHONNOUSERSITE=1"


:: ---------------------------
:: CẤU HÌNH
:: ---------------------------
set "PY_VERSION=3.13.5"         :: Phiên bản sẽ cài nếu cần
set "PY_MIN_VERSION=3.13.5"     :: Nếu Python hiện có cao hơn bản hiện tại
:: Nếu muốn cài vào thư mục cố định, bỏ comment dòng dưới:
:: set "TARGET_DIR=C:\Python313"
set "INSTALL_ALL_USERS=1"
set "PREPEND_PATH=1"
set "INCLUDE_PIP=1"
set "INCLUDE_LAUNCHER=1"
set "INCLUDE_TEST=0"
set "SIMPLE_INSTALL=1"

:: (TÙY CHỌN) SHA256 của installer để đối chiếu, lấy từ python.org; để trống nếu không dùng
set "PY_SHA256="

:: Proxy (nếu cần). Ví dụ:
:: set "HTTP_PROXY=http://proxy.mycorp:8080"
:: set "HTTPS_PROXY=http://proxy.mycorp:8080"
if defined HTTP_PROXY set "CURL_PROXY=--proxy %HTTP_PROXY%"
if defined HTTPS_PROXY set "CURL_PROXY=--proxy %HTTPS_PROXY%"

set "REQ_FILE=%~dp0modules\requirements.txt"
set "VENV_DIR=%~dp0.venv"
set "DEPS_FLAG=%VENV_DIR%\deps_installed.flag"

:: ---------------------------
:: LOG
:: ---------------------------

set "LOG_FILE=%~dp0setup_logs.log"

set "NL=^"

call :log "[INFO] Script started at %date% %time%"

:: ---------------------------
:: Always reset virtual environment on every run
:: ---------------------------
::if exist "%VENV_DIR%" (
    ::echo [INFO] Removing existing virtual environment at "%VENV_DIR%"...
    ::call :log "[INFO] Removing existing virtual environment at %VENV_DIR%"
    ::rmdir /s /q "%VENV_DIR%" 2>nul
::)

:: (Nếu anh có dùng cờ deps cũ, xoá luôn để tránh hiểu lầm)
::if exist "%DEPS_FLAG%" (
    ::del /f /q "%DEPS_FLAG%" >nul 2>&1
::)


:: ========================================================================
:: (BỔ SUNG) FAST PATH #1: Nếu venv đã có sẵn, bỏ qua admin & cài đặt
:: ========================================================================
if exist "%VENV_DIR%\Scripts\python.exe" (
    call :log "[INFO] Existing virtual environment detected: %VENV_DIR%\Scripts\python.exe — skipping elevation and Python installation."
    set "PY_CMD=%VENV_DIR%\Scripts\python.exe"
    set "PY_RUN=%VENV_DIR%\Scripts\python.exe"
    goto :activate_venv
)

:: ========================================================================
:: (BỔ SUNG) FAST PATH #2: Nếu đã có Python
:: ========================================================================
set "SKIP_ADMIN=0"
set "TMP_VER="
for %%I in (py python python3) do (
    where %%I >nul 2>&1 && (
        for /f "usebackq tokens=2 delims== " %%v in (`%%I -V 2^>^&1`) do set "TMP_VER=%%v"
        if defined TMP_VER (
            call :ver2num "%TMP_VER%" __cur
            call :ver2num "%PY_MIN_VERSION%" __min
            if !__cur! GEQ !__min! set "SKIP_ADMIN=1"
            set "TMP_VER="
            goto :done_fast_check
        )
    )
)
:done_fast_check
if "%SKIP_ADMIN%"=="1" (
    call :log "[INFO] Python >= %PY_MIN_VERSION% found — skipping elevation."
    goto :after_admin_check
)

:: ---------------------------
:: Kiểm tra quyền Admin (cần cho InstallAllUsers)
:: ---------------------------
>nul 2>&1 net session
if %errorlevel% neq 0 (
    call :log "[WARN] Administrator privileges not detected. Attempting elevation..."
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    if %errorlevel% neq 0 (
        call :log "[ERROR] Elevation failed. Please re-run this script as Administrator."
        pause
        exit /b 1
    )
    exit /b
)

:after_admin_check
:: ---------------------------
:: Phát hiện kiến trúc hệ thống
:: ---------------------------
set "ARCH=x64"
if /i "%PROCESSOR_ARCHITECTURE%"=="x86" (
    if defined PROCESSOR_ARCHITEW6432 ( set "ARCH=x64" ) else ( set "ARCH=x86" )
)
call :log "[INFO] System architecture: %ARCH%"

:: ---------------------------
:: Tạo URL & đường dẫn installer
:: ---------------------------
set "BASE_URL=https://www.python.org/ftp/python/%PY_VERSION%"
if /i "%ARCH%"=="x64" ( set "PY_FILENAME=python-%PY_VERSION%-amd64.exe" ) else ( set "PY_FILENAME=python-%PY_VERSION%.exe" )
set "PY_URL=%BASE_URL%/%PY_FILENAME%"
set "PY_INSTALLER=%TEMP%\%PY_FILENAME%"
::call :log "[DEBUG] Installer URL: %PY_URL%"

:: ---------------------------
:: Kiểm tra Python sẵn có
:: ---------------------------
set "PY_CMD="
set "PY_CUR_VER="
for %%I in (py python python3) do (
    where %%I >nul 2>&1 && (
        for /f "usebackq tokens=2 delims== " %%v in (`%%I -V 2^>^&1`) do set "PY_CUR_VER=%%v"
        if defined PY_CUR_VER (
            set "PY_CMD=%%I"
            goto :have_py
        )
    )
)
:have_py
if defined PY_CUR_VER (
    call :log "[INFO] Python detected: %PY_CMD% (version %PY_CUR_VER%)"
) else (
    call :log "[INFO] No Python detected on PATH."
)

:: ---------------------------
:: So sánh phiên bản:
:: ---------------------------
set "NEED_INSTALL=1"
if defined PY_CUR_VER (
    call :ver2num "%PY_CUR_VER%" CURVAL
    call :ver2num "%PY_MIN_VERSION%" MINVAL
    if !CURVAL! GEQ !MINVAL! (
        set "NEED_INSTALL=0"
        call :log "[INFO] Existing Python (=%PY_CUR_VER%) meets requirement (=%PY_MIN_VERSION%). Skipping installation."
    ) else (
        call :log "[INFO] Existing Python (=%PY_CUR_VER%) is below requirement (=%PY_MIN_VERSION%). Will install %PY_VERSION%."
    )
) else (
    call :log "[INFO] Python not found. Will install %PY_VERSION%."
)

if "%NEED_INSTALL%"=="0" (
    goto :post_install_path_patch
)

:: ---------------------------
:: Cảnh báo Pending Reboot (nếu có)
:: ---------------------------
set "PENDING=0"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" >nul 2>&1 && set "PENDING=1"
reg query "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" >nul 2>&1 && set "PENDING=1"
reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager" /v PendingFileRenameOperations >nul 2>&1 && set "PENDING=1"
if "%PENDING%"=="1" (
    call :log "[WARN] Pending reboot detected. Consider restarting Windows before installation to avoid setup issues."
)

:: ---------------------------
:: TẢI INSTALLER (curl PowerShell) có retry + timeout + Unblock-File
:: ---------------------------
if exist "%PY_INSTALLER%" del /f /q "%PY_INSTALLER%" >nul 2>&1
call :log "[INFO] Downloading installer to: %PY_INSTALLER%"

set "DL_OK=0"
for /L %%R in (1,1,3) do (
    call :log "[INFO] Download attempt %%R..."
    where curl >nul 2>&1
    if %errorlevel%==0 (
        curl -L %CURL_PROXY% --connect-timeout 30 --max-time 600 -o "%PY_INSTALLER%" "%PY_URL%" >>"%LOG_FILE%" 2>&1
    ) else (
        powershell -NoProfile -ExecutionPolicy Bypass -Command ^
            "try { $wc = New-Object Net.WebClient; if($env:HTTPS_PROXY){$wc.Proxy = New-Object Net.WebProxy($env:HTTPS_PROXY)}; $wc.DownloadFile('%PY_URL%','%PY_INSTALLER%') } catch { exit 1 }"
        if %errorlevel% neq 0 ( call :log "[WARN] PowerShell download attempt failed." )
    )

    if exist "%PY_INSTALLER%" (
        powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Unblock-File -Path '%PY_INSTALLER%' -ErrorAction SilentlyContinue } catch {}"
        set "DL_OK=1"
        goto :dl_done
    ) else (
        call :log "[WARN] Download failed on attempt %%R. Retrying in 5 seconds..."
        timeout /t 5 >nul
    )
)
:dl_done

if "%DL_OK%"=="0" (
    call :log "[ERROR] Installer not found after 3 attempts."
    echo [ERROR] Installer download failed. See log: %LOG_FILE%
    pause
    exit /b 3
)
call :log "[INFO] Installer downloaded successfully."

:: ---------------------------
:: Kiểm tra SHA256 (tùy chọn)
:: ---------------------------
if defined PY_SHA256 (
    for /f "tokens=1" %%H in ('certutil -hashfile "%PY_INSTALLER%" SHA256 ^| find /i /v "SHA256" ^| find /i /v "certutil"') do set "FILE_SHA=%%H"
    call :log "[INFO] SHA256 expected: %PY_SHA256%"
    call :log "[INFO] SHA256 actual  : %FILE_SHA%"
    if /i not "%FILE_SHA%"=="%PY_SHA256%" (
        call :log "[ERROR] Checksum mismatch. Aborting installation."
        echo [ERROR] Checksum mismatch. Delete the installer and try again.
        del /f /q "%PY_INSTALLER%" >nul 2>&1
        pause
        exit /b 12
    )
)

:: ---------------------------
:: Tham số cài đặt
:: ---------------------------
set "INSTALL_ARGS=/quiet InstallAllUsers=%INSTALL_ALL_USERS% PrependPath=%PREPEND_PATH% Include_test=%INCLUDE_TEST% Include_pip=%INCLUDE_PIP% Include_launcher=%INCLUDE_LAUNCHER% SimpleInstall=%SIMPLE_INSTALL%"
if defined TARGET_DIR set "INSTALL_ARGS=%INSTALL_ARGS% TargetDir=\"%TARGET_DIR%\""
call :log "[INFO] Installer arguments: %INSTALL_ARGS%"

:: ---------------------------
:: Tiến hành cài đặt (im lặng)
:: ---------------------------
call :log "[INFO] Starting Python installation..."
"%PY_INSTALLER%" %INSTALL_ARGS% >>"%LOG_FILE%" 2>&1
set "EC=%ERRORLEVEL%"
if not "%EC%"=="0" (
    call :log "[ERROR] Python installation failed with exit code %EC%."
    echo [ERROR] Python installation failed. See log: %LOG_FILE%
    pause
    exit /b 4
)
call :log "[INFO] Python installation completed."

:: ---------------------------
:: Patch PATH tạm (dùng được ngay trong phiên CMD hiện tại)
:: ---------------------------
:post_install_path_patch
set "PY_BIN="
set "PY_SCRIPTS="
where py >nul 2>&1
if %errorlevel%==0 (
    for /f "usebackq tokens=*" %%P in (`py -0p ^| findstr /i "%PY_VERSION%"`) do (
        for %%A in ("%%P") do set "PY_BIN=%%~dpA"
    )
)
if defined PY_BIN (
    set "PY_BIN=%PY_BIN:~0,-1%"
    set "PY_SCRIPTS=%PY_BIN%\Scripts"
    ::call :log "[DEBUG] PATH patch: %PY_BIN% ; %PY_SCRIPTS%"
    set "PATH=%PY_BIN%;%PY_SCRIPTS%;%PATH%"
)

:: ---------------------------
:: Đảm bảo có thể gọi Python
:: ---------------------------
:ensure_py_cmd
set "PY_CMD="
for %%I in (py python python3) do (
    where %%I >nul 2>&1
    if not defined PY_CMD if ERRORLEVEL 0 set "PY_CMD=%%I"
)

if not defined PY_CMD (
    if defined TARGET_DIR (
        if exist "%TARGET_DIR%\python.exe" set "PY_CMD=%TARGET_DIR%\python.exe"
    )
)
if not defined PY_CMD (
    echo [ERROR] Python interpreter not found on PATH.
    echo [HINT ] Ensure Python is installed with "Add to PATH", or disable App Execution Aliases.
    call :log "[ERROR] Python interpreter not found after installation."
    pause
    exit /b 5
)
echo [INFO] Using Python command: %PY_CMD%
call :log "[INFO] Using Python command: %PY_CMD%"

:: ---------------------------
:: Ưu tiên dùng py launcher để gọi đúng bản 3.x
:: ---------------------------
set "PY_RUN=python"
where py >nul 2>&1 && set "PY_RUN=py -3"
:: Nếu muốn khóa đúng nhánh 3.13, bật dòng dưới:

:: ---------------------------
:: Tạo venv (sửa chữa nếu hỏng) + retry tạo bằng đường dẫn tuyệt đối
:: ---------------------------
if exist "%VENV_DIR%\Scripts\python.exe" (
    call :log "[INFO] Virtual environment is present."
) else if exist "%VENV_DIR%" (
    call :log "[WARN] Virtual environment appears corrupted. Recreating..."
    rmdir /s /q "%VENV_DIR%" 2>nul
)

if not exist "%VENV_DIR%" (
    echo [INFO] Creating a new virtual environment...
    call :log "[INFO] %PY_RUN% -m venv %VENV_DIR%"
    %PY_RUN% -m venv "%VENV_DIR%" >>"%LOG_FILE%" 2>&1
    if errorlevel 1 (
        if defined PY_BIN (
            call :log "[WARN] First attempt failed. Retrying venv creation using absolute interpreter path."
            "%PY_BIN%\python.exe" -m venv "%VENV_DIR%" >>"%LOG_FILE%" 2>&1
        )
    )
    if not exist "%VENV_DIR%\Scripts\python.exe" (
        call :log "[ERROR] Failed to create virtual environment."
        echo [ERROR] Cannot create virtual environment. See log: %LOG_FILE%
        pause
        exit /b 6
    )
) else (
    echo [INFO] Virtual environment already exists. Skipping creation.
)

:: ---------------------------
:: Kích hoạt venv
:: ---------------------------
:activate_venv
call "%VENV_DIR%\Scripts\activate"
if errorlevel 1 (
    echo [ERROR] Failed to activate the virtual environment.
    call :log "[ERROR] Failed to activate the virtual environment."
    pause
    exit /b 7
)

:: ---------------------------
:: Cập nhật pip & luôn kiểm tra/cài dependencies (retry tối đa 3 lần) - dùng pip của venv
:: ---------------------------
echo [INFO] Verifying and installing dependencies from requirements (if any)...
set "PIP_TRY=0"
:retry_pip
set /a PIP_TRY+=1

"%VENV_DIR%\Scripts\python.exe" -m pip install --upgrade pip >>"%LOG_FILE%" 2>&1

if exist "%REQ_FILE%" (
    echo [INFO] Using requirements: "%REQ_FILE%"
    "%VENV_DIR%\Scripts\python.exe" -m pip install -r "%REQ_FILE%" >>"%LOG_FILE%" 2>&1
) else (
    echo [WARN] requirements.txt not found at "%REQ_FILE%". Skipping package installation.
    goto :after_deps
)

if errorlevel 1 (
    if %PIP_TRY% lss 3 (
        call :log "[WARN] pip failed, retrying (%PIP_TRY%/3) in 5 seconds..."
        timeout /t 5 >nul
        goto :retry_pip
    ) else (
        call :log "[ERROR] pip failed after 3 attempts."
        echo [ERROR] Dependency installation failed. See log: %LOG_FILE%
    )
) else (
    echo [INFO] Dependencies are up to date or installed successfully.
)

:after_deps


:: ---------------------------
:: Chạy main.py (UTF-8) tại thư mục gốc (không dùng \source)
:: ---------------------------
echo [INFO] Launching main.py...
"%VENV_DIR%\Scripts\python.exe" -X utf8 "%~dp0main.py"
set "RUN_EC=%ERRORLEVEL%"

if not "%RUN_EC%"=="0" (
    call :log "[ERROR] main.py exited with code %RUN_EC%."
    echo [ERROR] main.py failed (exit code %RUN_EC%). See log: %LOG_FILE%
    echo.
    echo === End of run.bat ===
    exit /b %RUN_EC%
)

call :log "[INFO] main.py completed successfully."
echo [INFO] Completed running main.py.
echo.
echo [INFO] Log file: %LOG_FILE%
exit /b 0


:: ===========================
:: HÀM: Ghi log
:: ===========================
:log
echo [%date% %time%] %~1
>>"%LOG_FILE%" echo [%date% %time%] %~1
exit /b

:: ===========================
:: HÀM: Chuẩn hoá version "A.B.C[rcX]" -> số A*1_000_000 + B*1_000 + C
::  - Làm sạch hậu tố rc/a/b để so sánh số học bền vững
:: ===========================
:ver2num
setlocal EnableDelayedExpansion
set "_v=%~1"
for /f "tokens=1 delims=abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-" %%S in ("%_v%") do set "_v=%%S"
set "_maj=0" & set "_min=0" & set "_pat=0"
for /f "tokens=1-3 delims=." %%A in ("%_v%") do (
    set "_maj=%%A" & set "_min=%%B" & set "_pat=%%C"
)
if not defined _min set "_min=0"
if not defined _pat set "_pat=0"
set /a "_val=_maj*1000000 + _min*1000 + _pat"
endlocal & set "%~2=%_val%"
exit /b
