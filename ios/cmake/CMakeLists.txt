cmake_minimum_required(VERSION 3.24)
project(BearBirdPadRT64IOS LANGUAGES C CXX OBJC OBJCXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    message(FATAL_ERROR "This harness must be configured with -DCMAKE_SYSTEM_NAME=iOS")
endif()

get_filename_component(BEARBIRDPAD_ROOT "${CMAKE_CURRENT_LIST_DIR}/../.." ABSOLUTE)
set(RT64_SOURCE_DIR "${BEARBIRDPAD_ROOT}/sources/banjo/lib/rt64")

foreach(host_tool DXC_PATH SPIRV_CROSS_MSL_PATH FILE_TO_C_PATH)
    if(NOT DEFINED ${host_tool} OR NOT EXISTS "${${host_tool}}")
        message(FATAL_ERROR "${host_tool} must point to an existing macOS host executable")
    endif()
endforeach()

if(NOT SDL2_INCLUDE_DIRS OR NOT EXISTS "${SDL2_INCLUDE_DIRS}/SDL.h")
    message(FATAL_ERROR "SDL2_INCLUDE_DIRS must contain SDL.h")
endif()

set(RT64_STATIC ON CACHE BOOL "" FORCE)
set(RT64_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

add_subdirectory("${RT64_SOURCE_DIR}" rt64)
