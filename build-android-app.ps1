# build-android-app.ps1 - Native PowerShell Android App Builder
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "AndiRun Android App Automated Builder & Installer" -ForegroundColor Cyan
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
    Write-Host "[*] Connect phone via USB-C and enable USB Debugging."
    exit 1
}

$device = ($deviceLines[0] -split "\s+")[0]
Write-Host "[✓] Selected Android Device: $device" -ForegroundColor Green

Set-Location "C:\projects\andirun\andirun-android"

if (-not (Test-Path "gradlew.bat")) {
    Write-Host "[-] Error: gradlew.bat not found in andirun-android directory." -ForegroundColor Red
    exit 1
}

Write-Host "[*] Building AndiRun Android App (Debug APK)..."
cmd.exe /c ".\gradlew.bat assembleDebug"

$apkPath = "app\build\outputs\apk\debug\app-debug.apk"
if (-not (Test-Path $apkPath)) {
    Write-Host "[-] APK build failed or not found at $apkPath." -ForegroundColor Yellow
    Write-Host "[*] You can build and run it directly by opening in Android Studio:"
    Write-Host "    C:\projects\andirun\andirun-android"
    exit 1
}

Write-Host "[✓] APK compiled successfully: $apkPath" -ForegroundColor Green
Write-Host "[*] Installing AndiRun Worker APK onto $device..."
& $adb -s $device install -r -g $apkPath

if ($LASTEXITCODE -eq 0) {
    Write-Host "[✓] Successfully installed AndiRun Worker on phone!" -ForegroundColor Green
    Write-Host "[*] Launching AndiRun Co-Processor Foreground Service..."
    & $adb -s $device shell am start-foreground-service -n com.andirun.worker/.WorkerService --ei PORT 8080 --es MODEL_PATH /data/local/tmp/tail-L20.gguf
    Write-Host "[✓] Service is active and listening on port 8080! You no longer need Termux." -ForegroundColor Green
} else {
    Write-Host "[-] Installation failed. Please check phone screen to grant install permissions." -ForegroundColor Red
}
