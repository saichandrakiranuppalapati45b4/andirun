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

echo [*] Checking for staged binary in /sdcard/Download/...
"%ADB%" -s %DEVICE% shell "test -f /sdcard/Download/llama-split-prefill && echo FOUND" > "%TEMP%\andirun_sd_check.txt" 2>&1
findstr "FOUND" "%TEMP%\andirun_sd_check.txt" >nul 2>&1
del "%TEMP%\andirun_sd_check.txt" >nul 2>&1

if %errorlevel% neq 0 (
    echo.
    echo [!] Notice: Android SELinux requires copying via shared storage (/sdcard/Download).
    echo [*] In Termux, run this command ONE time:
    echo.
    echo     cp bin/llama-split-prefill /sdcard/Download/ ^|^| cp build/bin/llama-split-prefill /sdcard/Download/
    echo.
    echo [*] (If Termux asks for storage permission, tap Allow).
    echo [*] Press any key after running the command in Termux...
    pause >nul
)

echo [*] Installing to /data/local/tmp/llama-split-prefill via ADB...
"%ADB%" -s %DEVICE% shell "cp /sdcard/Download/llama-split-prefill /data/local/tmp/llama-split-prefill && chmod 755 /data/local/tmp/llama-split-prefill"

"%ADB%" -s %DEVICE% shell "test -x /data/local/tmp/llama-split-prefill && echo FOUND" > "%TEMP%\andirun_bin_check.txt" 2>&1
findstr "FOUND" "%TEMP%\andirun_bin_check.txt" >nul 2>&1
del "%TEMP%\andirun_bin_check.txt" >nul 2>&1

if %errorlevel% equ 0 (
    echo [✓] Successfully installed worker binary to /data/local/tmp/!
    goto :start_daemon
)

echo [-] Error: Failed to install worker binary. Please check file copy in Termux.
exit /b 1

:start_daemon
echo [*] Launching background daemon on port 8080...
"%ADB%" -s %DEVICE% shell "pkill -f llama-split-prefill 2>/dev/null; nohup /data/local/tmp/llama-split-prefill --serve-tail 8080 --tail-model /data/local/tmp/tail-L20.gguf > /data/local/tmp/worker.log 2>&1 &"

timeout /t 2 /nobreak >nul

echo [*] Configuring port 8080 USB forward...
"%ADB%" -s %DEVICE% forward tcp:8080 tcp:8080
echo [✓] Background worker daemon is running on phone (:8080)!
echo [✓] You can now run serve_win_android.py without opening Termux.
