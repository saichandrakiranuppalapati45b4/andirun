@echo off
setlocal

set "VS_LOADED=0"
set "VCVARS_ALL=C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat"
set "VCVARS_64=C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"

if exist "%VCVARS_ALL%" (
    echo [*] Loading Visual Studio 64-bit environment with Windows 11 SDK 10.0.26100.0...
    call "%VCVARS_ALL%" x64 10.0.26100.0
    set "VS_LOADED=1"
) else if exist "%VCVARS_64%" (
    echo [*] Loading Visual Studio 64-bit environment via vcvars64.bat...
    call "%VCVARS_64%"
    set "VS_LOADED=1"
)

if "%VS_LOADED%"=="0" (
    echo [-] Error: Visual Studio environment initialization script not found!
    exit /b 1
)

set "INCLUDE=C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\ucrt;C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\um;C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0\shared;%INCLUDE%"
set "LIB=C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\ucrt\x64;C:\Program Files (x86)\Windows Kits\10\Lib\10.0.26100.0\um\x64;%LIB%"

cd /d "C:\projects\andirun\andirun-main\phone-attn"
if not exist build mkdir build

echo [*] Compiling pa-tool.exe (Vulkan Attention Worker)...
cl.exe /O2 /std:c++17 /EHsc /DNOMINMAX /D_CRT_SECURE_NO_WARNINGS /I. pa-tool.cpp pa-vulkan.cpp ws2_32.lib /Fe:build\pa-tool.exe

if %errorlevel% equ 0 (
    echo [✓] Successfully compiled build\pa-tool.exe!
) else (
    echo [ERROR] Compilation failed.
    exit /b 1
)
