# build-host.ps1 - Invokes Visual Studio environment and compiles llama-server

$ProjectRoot = $PSScriptRoot
$BatPath = "$ProjectRoot\build-host.bat"

& cmd.exe /c "`"$BatPath`""
