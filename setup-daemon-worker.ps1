# setup-daemon-worker.ps1 - Native PowerShell Background Daemon Setup
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "AndiRun Background Daemon Setup (No Termux Needed)" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$adb = "C:\projects\andirun\platform-tools\adb.exe"
if (-not (Test-Path $adb)) {
    $adb = "adb"
}

Write-Host "[*] Checking connected Android devices via $adb..."
$devicesOutput = & $adb devices
$deviceLines = $devicesOutput | Where-Object { $_ -match "\bdevice$" }

if (-not $deviceLines) {
    Write-Host "[-] Error: No Android phone detected via USB debugging." -ForegroundColor Red
    Write-Host "[*] Ensure phone is connected via USB-C and USB Debugging is enabled."
    exit 1
}

$device = ($deviceLines[0] -split "\s+")[0]
Write-Host "[✓] Connected Phone: $device" -ForegroundColor Green

Write-Host "[*] Checking for llama-split-prefill in /data/local/tmp/..."
$binCheck = & $adb -s $device shell "test -x /data/local/tmp/llama-split-prefill && echo FOUND"

if ($binCheck -match "FOUND") {
    Write-Host "[✓] /data/local/tmp/llama-split-prefill already installed and executable!" -ForegroundColor Green
} else {
    Write-Host "[*] Checking for staged binary in /sdcard/Download/..."
    $sdCheck = & $adb -s $device shell "test -f /sdcard/Download/llama-split-prefill && echo FOUND"
    
    if ($sdCheck -notmatch "FOUND") {
        Write-Host ""
        Write-Host "[!] Notice: Android SELinux requires copying via shared storage (/sdcard/Download)." -ForegroundColor Yellow
        Write-Host "[*] In Termux, run this command ONE time:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    cp bin/llama-split-prefill /sdcard/Download/ || cp build/bin/llama-split-prefill /sdcard/Download/" -ForegroundColor White -BackgroundColor Black
        Write-Host ""
        Write-Host "[*] (If Termux asks for storage permission, tap Allow)."
        Read-Host "Press Enter after copying in Termux..."
    }

    Write-Host "[*] Installing to /data/local/tmp/llama-split-prefill via ADB..."
    & $adb -s $device shell "cp /sdcard/Download/llama-split-prefill /data/local/tmp/llama-split-prefill && chmod 755 /data/local/tmp/llama-split-prefill"
    
    $binCheck2 = & $adb -s $device shell "test -x /data/local/tmp/llama-split-prefill && echo FOUND"
    if ($binCheck2 -match "FOUND") {
        Write-Host "[✓] Successfully installed worker to /data/local/tmp/!" -ForegroundColor Green
    } else {
        Write-Host "[-] Could not install binary. Please ensure it was copied to /sdcard/Download/." -ForegroundColor Red
        exit 1
    }
}

Write-Host "[*] Launching background daemon on phone port 8080..."
& $adb -s $device shell "pkill -f llama-split-prefill 2>/dev/null; nohup /data/local/tmp/llama-split-prefill --serve-tail 8080 --tail-model /data/local/tmp/tail-L20.gguf > /data/local/tmp/worker.log 2>&1 &"

Start-Sleep -Seconds 2

Write-Host "[*] Forwarding port 8080 over USB..."
& $adb -s $device forward tcp:8080 tcp:8080

Write-Host "[✓] Background worker daemon is active and listening on port 8080!" -ForegroundColor Green
Write-Host "[✓] You can now run serve_win_android.py anytime without opening Termux." -ForegroundColor Green
