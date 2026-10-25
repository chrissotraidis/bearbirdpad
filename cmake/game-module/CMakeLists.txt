cmake_minimum_required(VERSION 3.28)
project(BearBirdPadGameModule LANGUAGES C CXX)
if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS" OR NOT CMAKE_OSX_ARCHITECTURES STREQUAL "arm64")
    message(FATAL_ERROR "Use PadMint's arm64 iOS module toolchain")
endif()
get_filename_component(BEARBIRDPAD_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(BEARBIRDPAD_GENERATED "" CACHE PATH "Verified private output from build-game-module.py")
set(BEARBIRDPAD_SOURCE "${BEARBIRDPAD_ROOT}/sources/banjo" CACHE PATH "Verified pinned public source")
find_package(Python3 REQUIRED COMPONENTS Interpreter)
execute_process(COMMAND "${Python3_EXECUTABLE}" "${BEARBIRDPAD_ROOT}/scripts/check-module-inputs.py" "${BEARBIRDPAD_GENERATED}" "${BEARBIRDPAD_SOURCE}"
    COMMAND_ERROR_IS_FATAL ANY)
include("${BEARBIRDPAD_ROOT}/cmake/ModuleIdentity.cmake")
bearbirdpad_module_identity("${BEARBIRDPAD_ROOT}" identity)
set(runtime "${BEARBIRDPAD_SOURCE}/lib/N64ModernRuntime")
set(source "${BEARBIRDPAD_GENERATED}")
file(GLOB generated CONFIGURE_DEPENDS "${source}/RecompiledFuncs/*.c" "${source}/RecompiledFuncs/*.cpp")
add_library(BearBirdPadGame SHARED ${generated}
    "${source}/rsp/n_aspMain.cpp" "${source}/RecompiledPatches/patches.c" "${source}/RecompiledPatches/patches_bin.c"
    "${source}/src/main/register_overlays.cpp" "${source}/src/main/register_patches.cpp"
    "${BEARBIRDPAD_ROOT}/ios/module/game_module_entry.cpp")
set_target_properties(BearBirdPadGame PROPERTIES C_STANDARD 11 CXX_STANDARD 20 CXX_STANDARD_REQUIRED ON
    CXX_SCAN_FOR_MODULES OFF C_VISIBILITY_PRESET hidden CXX_VISIBILITY_PRESET hidden
    VISIBILITY_INLINES_HIDDEN ON PREFIX "" OUTPUT_NAME "BearBirdPadGame")
target_include_directories(BearBirdPadGame PRIVATE "${BEARBIRDPAD_ROOT}/ios/module"
    "${source}/include" "${source}/RecompiledFuncs" "${source}/RecompiledPatches"
    "${runtime}/N64Recomp/include" "${runtime}/librecomp/include" "${runtime}/ultramodern/include"
    "${runtime}/thirdparty" "${runtime}/thirdparty/sse2neon" "${runtime}/thirdparty/concurrentqueue")
target_compile_definitions(BearBirdPadGame PRIVATE "BEARBIRDPAD_MODULE_ID=\"${identity}\"")
target_compile_options(BearBirdPadGame PRIVATE -fno-strict-aliasing -Wno-implicit-function-declaration
    -Wno-unused-variable -Wno-unused-but-set-variable "-ffile-prefix-map=${BEARBIRDPAD_ROOT}=.")
set_source_files_properties("${source}/RecompiledPatches/patches.c" PROPERTIES
    COMPILE_OPTIONS "-include;${BEARBIRDPAD_ROOT}/ios/module/patch_attributes.h;-include;${source}/RecompiledFuncs/funcs.h")
target_link_options(BearBirdPadGame PRIVATE "LINKER:-undefined,dynamic_lookup")
