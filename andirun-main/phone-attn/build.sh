#!/usr/bin/env bash
# Builds pa-tool (Vulkan Attention Worker) for Android (Termux / NDK), Linux, and Windows.
set -euo pipefail
D="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$D/build"

echo "[AndiRun] Compiling pa-tool with Vulkan Attention Acceleration..."

if [ -z "${CXX:-}" ]; then
    if command -v clang++ >/dev/null 2>&1; then
        CXX=clang++
    elif command -v g++ >/dev/null 2>&1; then
        CXX=g++
    elif command -v c++ >/dev/null 2>&1; then
        CXX=c++
    else
        CXX=clang++
    fi
fi
CXXFLAGS="-std=c++17 -O3 -Wall -Wextra"
LDFLAGS=""

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    LDFLAGS="-lws2_32"
elif [[ "$(uname -o 2>/dev/null)" == "Android" ]]; then
    LDFLAGS="-ldl"
else
    LDFLAGS="-lpthread -ldl"
fi

$CXX $CXXFLAGS "$D/pa-tool.cpp" "$D/pa-vulkan.cpp" $LDFLAGS -o "$D/build/pa-tool"
echo "[✓] Successfully built $D/build/pa-tool"
