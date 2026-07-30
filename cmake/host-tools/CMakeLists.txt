cmake_minimum_required(VERSION 3.24)
project(bearbirdpad_host_tools LANGUAGES C CXX)

set(CMAKE_C_STANDARD 17)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

set(BEARBIRDPAD_SOURCE_ROOT
    "${CMAKE_CURRENT_LIST_DIR}/../../sources/banjo"
    CACHE PATH "Pinned BanjoRecomp checkout")
get_filename_component(BEARBIRDPAD_SOURCE_ROOT
    "${BEARBIRDPAD_SOURCE_ROOT}" REALPATH)

set(n64recomp_source
    "${BEARBIRDPAD_SOURCE_ROOT}/lib/N64ModernRuntime/N64Recomp")
set(rt64_source "${BEARBIRDPAD_SOURCE_ROOT}/lib/rt64")
set(spirv_cross_source "${rt64_source}/src/contrib/spirv-cross")
set(xxhash_source
    "${BEARBIRDPAD_SOURCE_ROOT}/lib/N64ModernRuntime/thirdparty/xxHash")

foreach(required_path
        "${n64recomp_source}/CMakeLists.txt"
        "${rt64_source}/src/tools/file_to_c/file_to_c.cpp"
        "${rt64_source}/src/tools/spirv_cross_msl/spirv_cross_msl.cpp"
        "${spirv_cross_source}/CMakeLists.txt"
        "${xxhash_source}/xxhash.c"
        "${xxhash_source}/xxhash.h")
    if(NOT EXISTS "${required_path}")
        message(FATAL_ERROR
            "Missing pinned host-tool input: ${required_path}. "
            "Run scripts/fetch-sources.sh first.")
    endif()
endforeach()

add_subdirectory("${n64recomp_source}" n64recomp EXCLUDE_FROM_ALL)

add_library(xxhash STATIC "${xxhash_source}/xxhash.c")
target_include_directories(xxhash PUBLIC "${xxhash_source}")

set(SPIRV_CROSS_CLI OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_TESTS OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_GLSL ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_HLSL OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_MSL ON CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_CPP OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_REFLECT OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_C_API OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_ENABLE_UTIL OFF CACHE BOOL "" FORCE)
set(SPIRV_CROSS_SKIP_INSTALL ON CACHE BOOL "" FORCE)
add_subdirectory("${spirv_cross_source}" spirv-cross EXCLUDE_FROM_ALL)

add_executable(file_to_c
    "${rt64_source}/src/tools/file_to_c/file_to_c.cpp")
target_compile_features(file_to_c PRIVATE cxx_std_17)

add_executable(spirv_cross_msl
    "${rt64_source}/src/tools/spirv_cross_msl/spirv_cross_msl.cpp")
target_compile_features(spirv_cross_msl PRIVATE cxx_std_17)
target_include_directories(spirv_cross_msl PRIVATE "${spirv_cross_source}")
target_link_libraries(spirv_cross_msl PRIVATE
    spirv-cross-core
    spirv-cross-msl)

add_executable(rom_xxh3 rom_xxh3.cpp)
target_compile_features(rom_xxh3 PRIVATE cxx_std_17)
target_link_libraries(rom_xxh3 PRIVATE xxhash)
