cmake_minimum_required(VERSION 3.14)
project(pa-tool CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(pa-tool
    pa-tool.cpp
    pa-vulkan.cpp
)

target_include_directories(pa-tool PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

if (WIN32)
    target_link_libraries(pa-tool PRIVATE ws2_32)
    target_compile_definitions(pa-tool PRIVATE NOMINMAX _CRT_SECURE_NO_WARNINGS)
else()
    target_link_libraries(pa-tool PRIVATE dl pthread)
endif()
