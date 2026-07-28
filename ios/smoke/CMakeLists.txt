cmake_minimum_required(VERSION 3.24)
project(BanjoPadMetalSmoke LANGUAGES C CXX OBJC OBJCXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    message(FATAL_ERROR "The smoke app requires -DCMAKE_SYSTEM_NAME=iOS")
endif()

foreach(required_path PLUME_ARCHIVE PLUME_INCLUDE_DIR)
    if(NOT DEFINED ${required_path} OR NOT EXISTS "${${required_path}}")
        message(FATAL_ERROR "${required_path} must point to an existing Phase 1 artifact")
    endif()
endforeach()

find_package(SDL2 REQUIRED CONFIG)

add_library(plume STATIC IMPORTED GLOBAL)
set_target_properties(plume PROPERTIES
    IMPORTED_LOCATION "${PLUME_ARCHIVE}"
    INTERFACE_INCLUDE_DIRECTORIES "${PLUME_INCLUDE_DIR}"
)

add_executable(BanjoPadMetalSmoke MACOSX_BUNDLE main.cpp)
target_compile_features(BanjoPadMetalSmoke PRIVATE cxx_std_17)
target_compile_definitions(BanjoPadMetalSmoke PRIVATE PLUME_IOS=1)
target_link_libraries(BanjoPadMetalSmoke PRIVATE
    plume
    SDL2::SDL2main
    SDL2::SDL2-static
    "-framework Foundation"
    "-framework UIKit"
    "-framework Metal"
    "-framework QuartzCore"
    "-framework CoreGraphics"
)

set_target_properties(BanjoPadMetalSmoke PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic
    XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${DEVELOPMENT_TEAM}"
    XCODE_ATTRIBUTE_OTHER_LDFLAGS "-ObjC"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.chrissotraidis.banjopad.smoke"
    XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS "iphoneos iphonesimulator"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
)
