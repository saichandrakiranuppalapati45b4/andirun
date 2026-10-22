#!/usr/bin/env bash
# build-android-worker.sh - Cross-compile Backburner worker for Android ARM64
# Supports Vulkan GPU, OpenCL (Adreno/Mali), and ARM KleidiAI/Neon CPU backends.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LLAMA="${ROOT}/llama.cpp"
TARGET="${1:-vulkan}"  # vulkan | opencl | cpu

NCPU=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)
JOBS="${JOBS:-$NCPU}"

# Locate Android NDK
if [ -z "${ANDROID_NDK:-}" ]; then
  CANDIDATE_PATHS=(
    "$HOME/Android/Sdk/ndk-bundle"
    "$HOME/Android/Sdk/ndk"/*
    "/mnt/c/Users/$USER/AppData/Local/Android/Sdk/ndk"/*
  )
  for p in "${CANDIDATE_PATHS[@]}"; do
    if [ -d "$p" ] && [ -f "$p/build/cmake/android.toolchain.cmake" ]; then
      ANDROID_NDK="$p"
      break
    fi
  done
fi

if [ -z "${ANDROID_NDK:-}" ] || [ ! -f "${ANDROID_NDK}/build/cmake/android.toolchain.cmake" ]; then
  echo "Error: ANDROID_NDK not found. Please export ANDROID_NDK=/path/to/android-ndk (r26 or newer)" >&2
  exit 1
fi

echo "==> Using Android NDK: $ANDROID_NDK"

OUT="${ROOT}/build-worker-android-${TARGET}"
CMAKE_ARGS=(
  -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK}/build/cmake/android.toolchain.cmake"
  -DANDROID_ABI=arm64-v8a
  -DANDROID_PLATFORM=android-31
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -DLLAMA_BUILD_TESTS=OFF
  -DLLAMA_BUILD_EXAMPLES=OFF
  -DLLAMA_OPENSSL=OFF
  -DGGML_NATIVE=OFF
  -DGGML_CPU_ARM_ARCH=armv8.7-a
  -DGGML_OPENMP=OFF
  -DGGML_LLAMAFILE=OFF
)

case "$TARGET" in
  vulkan)
    echo "==> Configuring Vulkan GPU backend..."
    CMAKE_ARGS+=(-DGGML_VULKAN=ON)
    ;;
  opencl)
    echo "==> Configuring OpenCL (Adreno/Mali) backend..."
    CMAKE_ARGS+=(-DGGML_OPENCL=ON)
    ;;
  cpu)
    echo "==> Configuring pure ARM64 CPU backend..."
    ;;
  *)
    echo "Unknown target: $TARGET (use vulkan, opencl, or cpu)" >&2
    exit 1
    ;;
esac

echo "==> Running CMake configure in $OUT..."
cmake -S "$LLAMA" -B "$OUT" "${CMAKE_ARGS[@]}"

echo "==> Compiling worker binaries (-j$JOBS)..."
cmake --build "$OUT" --config Release -j "$JOBS" --target llama-split-prefill llama-bench

echo "=========================================================="
echo "Build complete! Output binaries:"
echo "  - $OUT/bin/llama-split-prefill (Tail server)"
echo "  - $OUT/bin/llama-bench         (Hardware benchmark)"
echo ""
echo "Deploy to connected phone via ADB:"
echo "  adb push $OUT/bin/llama-split-prefill /data/local/tmp/"
echo "  adb shell chmod +x /data/local/tmp/llama-split-prefill"
echo "=========================================================="
