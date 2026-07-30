cmake_minimum_required(VERSION 3.24)
project(BearBirdPadCIStub LANGUAGES C CXX OBJC OBJCXX)

if(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")
    message(FATAL_ERROR "The CI stub requires -DCMAKE_SYSTEM_NAME=iOS")
endif()

find_package(SDL2 REQUIRED CONFIG)

add_executable(BearBirdPadCIStub MACOSX_BUNDLE main.mm)
target_compile_features(BearBirdPadCIStub PRIVATE cxx_std_17)
target_link_libraries(BearBirdPadCIStub PRIVATE
    SDL2::SDL2main
    SDL2::SDL2-static
    "-framework Foundation"
    "-framework UIKit"
    "-framework Metal"
    "-framework QuartzCore"
)

set_target_properties(BearBirdPadCIStub PROPERTIES
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/Info.plist.in"
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic
    XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${DEVELOPMENT_TEAM}"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.chrissotraidis.bearbirdpad.ci-stub"
    XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS "iphoneos iphonesimulator"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
)
