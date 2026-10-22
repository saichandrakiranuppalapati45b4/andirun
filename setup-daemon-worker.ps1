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
    Write-Host "[*] Checking if Termux can copy the binary to /data/local/tmp/..."
    & $adb -s $device shell "su -c 'cp /data/data/com.termux/files/home/andirun/andirun-main/llama.cpp/build/bin/llama-split-prefill /data/local/tmp/' 2>/dev/null"
    & $adb -s $device shell "chmod 755 /data/local/tmp/llama-split-prefill 2>/dev/null"
    
    $binCheck2 = & $adb -s $device shell "test -x /data/local/tmp/llama-split-prefill && echo FOUND"
    if ($binCheck2 -match "FOUND") {
        Write-Host "[✓] Successfully staged worker binary to /data/local/tmp/!" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "[!] Notice: The binary is currently inside Termux's private storage." -ForegroundColor Yellow
        Write-Host "[*] Please run this one-line command inside Termux on your phone ONCE:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    cp ~/andirun/andirun-main/llama.cpp/build/bin/llama-split-prefill /data/local/tmp/ && chmod 755 /data/local/tmp/llama-split-prefill" -ForegroundColor White -BackgroundColor Black
        Write-Host ""
        Write-Host "[*] Once copied, you NEVER have to open Termux again!"
        Read-Host "Press Enter after running the command in Termux..."
    }
}

Write-Host "[*] Launching background daemon on phone port 8080..."
& $adb -s $device shell "pkill -f llama-split-prefill 2>/dev/null; nohup /data/local/tmp/llama-split-prefill --serve-tail 8080 --tail-model /data/local/tmp/tail-L20.gguf > /data/local/tmp/worker.log 2>&1 &"

Start-Sleep -Seconds 2

Write-Host "[*] Forwarding port 8080 over USB..."
& $adb -s $device forward tcp:8080 tcp:8080

Write-Host "[✓] Background worker daemon is active and listening on port 8080!" -ForegroundColor Green
Write-Host "[✓] You can now run serve_win_android.py anytime without opening Termux." -ForegroundColor Green
