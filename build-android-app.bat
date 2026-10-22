@echo off
setlocal enabledelayedexpansion

echo [*] ============================================================
echo [*] AndiRun Android App Automated Builder & Installer
echo [*] ============================================================

set "ADB=C:\projects\andirun\platform-tools\adb.exe"
if not exist "%ADB%" (
    set "ADB=adb"
)

echo [*] Detecting connected Android phone...
"%ADB%" devices | findstr /R /C:"[a-zA-Z0-9].*device$" >nul
if %errorlevel% neq 0 (
    echo [-] Error: No Android phone detected via USB debugging.
    echo [*] Connect phone via USB-C and enable USB Debugging.
    exit /b 1
)

for /f "tokens=1" %%d in ('"%ADB%" devices ^| findstr /R /C:"[a-zA-Z0-9].*device$"') do (
    set "DEVICE=%%d"
    goto :found_device
)

:found_device
echo [✓] Selected Android Device: !DEVICE!

cd /d "C:\projects\andirun\andirun-android"

echo [*] Checking Gradle wrapper...
if not exist "gradlew.bat" (
    echo [-] Error: gradlew.bat not found in andirun-android directory.
    exit /b 1
)

echo [*] Building AndiRun Android App (Debug APK)...
call gradlew.bat assembleDebug

if %errorlevel% neq 0 (
    echo [-] Gradle build failed.
    echo [*] If Android SDK is not in PATH, please open the project in Android Studio:
    echo [*] C:\projects\andirun\andirun-android
    exit /b 1
)

set "APK_PATH=app\build\outputs\apk\debug\app-debug.apk"
if not exist "%APK_PATH%" (
    echo [-] Error: APK not found at %APK_PATH%
    exit /b 1
)

echo [✓] APK compiled successfully: %APK_PATH%
echo [*] Installing AndiRun Worker APK onto !DEVICE!...
"%ADB%" -s !DEVICE! install -r -g "%APK_PATH%"

if %errorlevel% equ 0 (
    echo [✓] Successfully installed AndiRun Worker on phone!
    echo [*] Launching AndiRun Co-Processor Foreground Service...
    "%ADB%" -s !DEVICE! shell am start-foreground-service -n com.andirun.worker/.WorkerService --ei PORT 8080 --es MODEL_PATH /data/local/tmp/tail-L20.gguf
    echo [✓] Service is active and listening on port 8080! You no longer need Termux.
) else (
    echo [-] Installation failed. Check phone screen to allow installation over USB.
    exit /b 1
)
