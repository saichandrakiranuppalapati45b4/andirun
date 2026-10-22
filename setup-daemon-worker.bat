@echo off
setlocal enabledelayedexpansion

echo [*] ============================================================
echo [*] AndiRun Background Daemon Setup (No Termux Needed)
echo [*] ============================================================

set "ADB=C:\projects\andirun\platform-tools\adb.exe"
if not exist "%ADB%" set "ADB=adb"

echo [*] Checking connected Android devices via %ADB%...
"%ADB%" devices > "%TEMP%\andirun_devices.txt" 2>&1

set "DEVICE="
for /f "skip=1 tokens=1,2" %%A in (%TEMP%\andirun_devices.txt) do (
    if "%%B"=="device" (
        set "DEVICE=%%A"
        goto :found_device
    )
)

if not defined DEVICE (
    type "%TEMP%\andirun_devices.txt"
    echo [-] Error: No Android phone detected via USB debugging.
    echo [*] Ensure phone is connected via USB-C with USB Debugging enabled.
    del "%TEMP%\andirun_devices.txt" >nul 2>&1
    exit /b 1
)

:found_device
del "%TEMP%\andirun_devices.txt" >nul 2>&1
echo [✓] Connected Phone: %DEVICE%

echo [*] Checking for llama-split-prefill in /data/local/tmp/...
"%ADB%" -s %DEVICE% shell "test -x /data/local/tmp/llama-split-prefill && echo FOUND" > "%TEMP%\andirun_bin_check.txt" 2>&1
findstr "FOUND" "%TEMP%\andirun_bin_check.txt" >nul 2>&1
del "%TEMP%\andirun_bin_check.txt" >nul 2>&1

if %errorlevel% equ 0 (
    echo [✓] /data/local/tmp/llama-split-prefill already installed and executable!
    goto :start_daemon
)

echo [*] Worker binary not yet in /data/local/tmp/.
echo [*] Checking if Termux can copy it to /data/local/tmp/...
"%ADB%" -s %DEVICE% shell "su -c 'cp /data/data/com.termux/files/home/andirun/andirun-main/llama.cpp/build/bin/llama-split-prefill /data/local/tmp/' 2>/dev/null"
"%ADB%" -s %DEVICE% shell "chmod 755 /data/local/tmp/llama-split-prefill 2>/dev/null"

"%ADB%" -s %DEVICE% shell "test -x /data/local/tmp/llama-split-prefill && echo FOUND" > "%TEMP%\andirun_bin_check.txt" 2>&1
findstr "FOUND" "%TEMP%\andirun_bin_check.txt" >nul 2>&1
del "%TEMP%\andirun_bin_check.txt" >nul 2>&1

if %errorlevel% equ 0 (
    echo [✓] Successfully staged worker binary to /data/local/tmp/!
    goto :start_daemon
)

echo [!] Notice: The binary is inside Termux's private storage.
echo [*] Please run this one-line command inside Termux on your phone ONCE:
echo.
echo     cp ~/andirun/andirun-main/llama.cpp/build/bin/llama-split-prefill /data/local/tmp/ && chmod 755 /data/local/tmp/llama-split-prefill
echo.
echo [*] Once copied, you never have to open Termux again!
echo [*] Press any key after running the command in Termux...
pause >nul

:start_daemon
echo [*] Launching background daemon on port 8080...
"%ADB%" -s %DEVICE% shell "pkill -f llama-split-prefill 2>/dev/null; nohup /data/local/tmp/llama-split-prefill --serve-tail 8080 --tail-model /data/local/tmp/tail-L20.gguf > /data/local/tmp/worker.log 2>&1 &"

timeout /t 2 /nobreak >nul

echo [*] Configuring port 8080 USB forward...
"%ADB%" -s %DEVICE% forward tcp:8080 tcp:8080
echo [✓] Background worker daemon is running on phone (:8080)!
echo [✓] You can now run serve_win_android.py without opening Termux.
