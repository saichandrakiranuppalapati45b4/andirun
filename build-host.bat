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
set "PATH=C:\projects\andirun\platform-tools;C:\Program Files\CMake\bin;%PATH%"

cd /d "C:\projects\andirun"

rem Do not clean build-win every time to allow fast incremental Ninja builds
rem if exist "build-win" rmdir /s /q "build-win"

echo [*] Running CMake configuration with Ninja and MSVC cl.exe...
cmake -S andirun-main\llama.cpp -B build-win -G Ninja ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_C_COMPILER=cl ^
  -DCMAKE_CXX_COMPILER=cl ^
  -DCMAKE_CXX_FLAGS="/EHsc /DNOMINMAX" ^
  -DCMAKE_C_FLAGS="/DNOMINMAX" ^
  -DLLAMA_BUILD_TESTS=OFF ^
  -DLLAMA_BUILD_EXAMPLES=ON ^
  -DLLAMA_OPENSSL=OFF ^
  -DBUILD_SHARED_LIBS=OFF

if %errorlevel% neq 0 (
    echo [-] CMake configuration failed.
    exit /b %errorlevel%
)

echo [*] Compiling llama-server Release...
cmake --build build-win --target llama-server -j
if %errorlevel% neq 0 (
    echo [-] Build failed.
    exit /b %errorlevel%
)

echo.
echo ========================================================
echo [✓] Build completed successfully!
echo Executable located at:
echo     C:\projects\andirun\build-win\bin\llama-server.exe
echo ========================================================
