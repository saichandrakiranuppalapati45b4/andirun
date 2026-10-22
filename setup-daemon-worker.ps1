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
& $adb -s $device shell test -x /data/local/tmp/llama-split-prefill
$binInstalled = ($LASTEXITCODE -eq 0)

if ($binInstalled) {
    Write-Host "[✓] /data/local/tmp/llama-split-prefill already installed and executable!" -ForegroundColor Green
} else {
    $localBin = "C:\projects\andirun\llama-split-prefill"
    if (Test-Path $localBin) {
        Write-Host "[*] Found local binary on PC. Pushing to /data/local/tmp/..." -ForegroundColor Cyan
        & $adb -s $device push $localBin /data/local/tmp/llama-split-prefill
        & $adb -s $device shell chmod 755 /data/local/tmp/llama-split-prefill
    } else {
        # Check if HTTP transfer server is running on Termux
        & $adb -s $device forward tcp:8081 tcp:8081
        $streamed = $false
        try {
            Write-Host "[*] Probing for Termux HTTP stream on :8081..."
            Invoke-WebRequest -Uri "http://127.0.0.1:8081/llama-split-prefill" -OutFile $localBin -TimeoutSec 3 -ErrorAction Stop
            if (Test-Path $localBin) {
                Write-Host "[✓] Successfully streamed binary from Termux to PC!" -ForegroundColor Green
                & $adb -s $device push $localBin /data/local/tmp/llama-split-prefill
                & $adb -s $device shell chmod 755 /data/local/tmp/llama-split-prefill
                $streamed = $true
            }
        } catch {
            # HTTP server not active
        }

        if (-not $streamed) {
            Write-Host "[*] Checking for staged binary in /sdcard/Download/..."
            & $adb -s $device shell test -f /sdcard/Download/llama-split-prefill
            $inDownload = ($LASTEXITCODE -eq 0)

            if (-not $inDownload) {
                Write-Host ""
                Write-Host "[!] Choose Method A or Method B in Termux:" -ForegroundColor Yellow
                Write-Host ""
                Write-Host "[*] METHOD A (Standard Storage Permission):" -ForegroundColor Cyan
                Write-Host "    1. In Termux, run:  termux-setup-storage"
                Write-Host "    2. Tap ALLOW on the popup on your phone screen."
                Write-Host "    3. In Termux, run:  cp build/bin/llama-split-prefill ~/storage/downloads/"
                Write-Host ""
                Write-Host "[*] METHOD B (Direct USB Stream - No Storage Permission):" -ForegroundColor Cyan
                Write-Host "    In Termux, run:     python -m http.server 8081 --directory build/bin"
                Write-Host ""
                Read-Host "Press Enter after completing Method A or Method B in Termux..."

                # Try stream after user action
                try {
                    Invoke-WebRequest -Uri "http://127.0.0.1:8081/llama-split-prefill" -OutFile $localBin -TimeoutSec 5 -ErrorAction Stop
                    if (Test-Path $localBin) {
                        & $adb -s $device push $localBin /data/local/tmp/llama-split-prefill
                        & $adb -s $device shell chmod 755 /data/local/tmp/llama-split-prefill
                    }
                } catch {}
            }

            # Check /sdcard/Download copy
            & $adb -s $device shell cp /sdcard/Download/llama-split-prefill /data/local/tmp/llama-split-prefill
            & $adb -s $device shell chmod 755 /data/local/tmp/llama-split-prefill
        }
    }

    & $adb -s $device shell test -x /data/local/tmp/llama-split-prefill
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[✓] Successfully installed worker to /data/local/tmp/!" -ForegroundColor Green
    } else {
        Write-Host "[-] Could not install binary. Please run Method A or Method B." -ForegroundColor Red
        exit 1
    }
}

Write-Host "[*] Launching background daemon on phone port 8080..."
& $adb -s $device shell pkill -f llama-split-prefill
& $adb -s $device shell "nohup /data/local/tmp/llama-split-prefill --serve-tail 8080 --tail-model /data/local/tmp/tail-L20.gguf > /data/local/tmp/worker.log 2>&1 &"

Start-Sleep -Seconds 2

Write-Host "[*] Forwarding port 8080 over USB..."
& $adb -s $device forward tcp:8080 tcp:8080

Write-Host "[✓] Background worker daemon is active and listening on port 8080!" -ForegroundColor Green
Write-Host "[✓] You can now run serve_win_android.py anytime without opening Termux." -ForegroundColor Green
