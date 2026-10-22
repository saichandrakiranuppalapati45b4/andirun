cmake_minimum_required(VERSION 3.22.1)
project("andirun_native")

set(CMAKE_CXX_STANDARD 17)

# Path to AndiRun llama.cpp
set(LLAMA_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../../../../andirun-main/llama.cpp")

include_directories(
    ${LLAMA_ROOT}
    ${LLAMA_ROOT}/include
    ${LLAMA_ROOT}/ggml/include
    ${LLAMA_ROOT}/tools/split-prefill
)

add_subdirectory(${LLAMA_ROOT} ${CMAKE_CURRENT_BINARY_DIR}/llama_build EXCLUDE_FROM_ALL)

add_library(
    andirun_native
    SHARED
    native-worker.cpp
)

target_link_libraries(
    andirun_native
    PRIVATE
    llama
    ggml
    log
    android
)
