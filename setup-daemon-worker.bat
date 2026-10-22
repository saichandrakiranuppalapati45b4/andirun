@echo off
setlocal enabledelayedexpansion

echo [*] ============================================================
echo [*] AndiRun Background Daemon Setup (No Termux Needed)
echo [*] ============================================================

set "ADB=C:\projects\andirun\platform-tools\adb.exe"
if not exist "%ADB%" (
    set "ADB=adb"
)

echo [*] Checking connected Android devices...
for /f "tokens=1" %%d in ('"%ADB%" devices ^| findstr /R /C:"[a-zA-Z0-9].*device$"') do (
    set "DEVICE=%%d"
    goto :found_device
)

echo [-] Error: No Android phone detected via USB debugging.
exit /b 1

:found_device
echo [✓] Connected Phone: !DEVICE!

echo [*] Checking for llama-split-prefill in /data/local/tmp/...
"%ADB%" -s !DEVICE! shell "test -x /data/local/tmp/llama-split-prefill && echo FOUND" | findstr "FOUND" >nul
if %errorlevel% equ 0 (
    echo [✓] /data/local/tmp/llama-split-prefill already installed and executable!
    goto :start_daemon
)

echo [*] Searching for compiled binary inside Termux storage...
for /f "tokens=*" %%f in ('"%ADB%" -s !DEVICE! shell "find /data/data/com.termux/files/home -name llama-split-prefill 2>/dev/null"') do (
    set "TERMUX_BIN=%%f"
    goto :copy_from_termux
)

echo [-] Could not locate llama-split-prefill automatically.
echo [*] If you have llama-split-prefill on your PC, you can push it directly:
echo [*]   adb push llama-split-prefill /data/local/tmp/
exit /b 1

:copy_from_termux
echo [✓] Found Termux binary at !TERMUX_BIN!
echo [*] Installing to /data/local/tmp/llama-split-prefill...
"%ADB%" -s !DEVICE! shell "cp '!TERMUX_BIN!' /data/local/tmp/llama-split-prefill && chmod 755 /data/local/tmp/llama-split-prefill"

:start_daemon
echo [*] Launching background daemon on port 8080...
"%ADB%" -s !DEVICE! shell "pkill -f llama-split-prefill 2>/dev/null; nohup /data/local/tmp/llama-split-prefill --serve-tail 8080 --tail-model /data/local/tmp/tail-L20.gguf > /data/local/tmp/worker.log 2>&1 &"

timeout /t 2 /nobreak >nul

echo [*] Testing port 8080 forward...
"%ADB%" -s !DEVICE! forward tcp:8080 tcp:8080
echo [✓] Background worker daemon is running on phone!
echo [✓] You can now run serve_win_android.py without opening Termux.
