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

# 1. Check if binary is already installed
Write-Host "[*] Checking /data/local/tmp/llama-split-prefill..."
& $adb -s $device shell test -x /data/local/tmp/llama-split-prefill
$installed = ($LASTEXITCODE -eq 0)

if (-not $installed) {
    # Try copy from /sdcard/Download/
    Write-Host "[*] Attempting to copy from /sdcard/Download/ to /data/local/tmp/..."
    & $adb -s $device shell cp /sdcard/Download/llama-split-prefill /data/local/tmp/llama-split-prefill
    & $adb -s $device shell chmod 755 /data/local/tmp/llama-split-prefill
    
    & $adb -s $device shell test -x /data/local/tmp/llama-split-prefill
    $installed = ($LASTEXITCODE -eq 0)

    if (-not $installed) {
        Write-Host ""
        Write-Host "[!] Binary not found in /sdcard/Download/." -ForegroundColor Yellow
        Write-Host "[*] In Termux, run this command to copy to Downloads:" -ForegroundColor Cyan
        Write-Host "    cp ~/andirun/andirun-main/llama.cpp/build/bin/llama-split-prefill /sdcard/Download/"
        Write-Host ""
        Read-Host "Press Enter after copying in Termux..."
        
        & $adb -s $device shell cp /sdcard/Download/llama-split-prefill /data/local/tmp/llama-split-prefill
        & $adb -s $device shell chmod 755 /data/local/tmp/llama-split-prefill
    }
}

& $adb -s $device shell test -x /data/local/tmp/llama-split-prefill
if ($LASTEXITCODE -eq 0) {
    Write-Host "[✓] Worker binary is installed at /data/local/tmp/llama-split-prefill!" -ForegroundColor Green
    Write-Host "[*] Starting background daemon on port 8080..."
    & $adb -s $device shell pkill -f llama-split-prefill
    & $adb -s $device shell "nohup /data/local/tmp/llama-split-prefill --serve-tail 8080 --tail-model /data/local/tmp/tail-L20.gguf > /data/local/tmp/worker.log 2>&1 &"
    Start-Sleep -Seconds 2
    
    Write-Host "[*] Setting up USB port forward (:8080)..."
    & $adb -s $device forward tcp:8080 tcp:8080
    
    Write-Host "[✓] Background worker daemon is running on phone (:8080)!" -ForegroundColor Green
    Write-Host "[✓] You can now close Termux and run serve_win_android.py anytime." -ForegroundColor Green
} else {
    Write-Host "[-] Failed to install worker to /data/local/tmp/." -ForegroundColor Red
    exit 1
}
