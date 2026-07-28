#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="--simulator"
PRODUCT="smoke"
CONFIG="Release"
SDL_VERSION="2.32.10"
SDL_SHA256="5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165"
FREETYPE_VERSION="2.13.3"
FREETYPE_SHA256="0550350666d427c74daeb85d5ac7bb353acba5f76956395995311a9c6f063289"
DEPS_ROOT="$ROOT/build-ios-deps"
DOWNLOAD_ROOT="$DEPS_ROOT/downloads"
SOURCE_ROOT="$DEPS_ROOT/sources"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --device|--simulator)
            MODE="$1"
            shift
            ;;
        --stub)
            PRODUCT="stub"
            shift
            ;;
        --config)
            CONFIG="${2:-}"
            if [[ "$CONFIG" != "Debug" && "$CONFIG" != "Release" ]]; then
                echo "--config must be Debug or Release" >&2
                exit 2
            fi
            shift 2
            ;;
        *)
            echo "Usage: scripts/build-ios.sh [--device|--simulator] [--stub] [--config Debug|Release]" >&2
            exit 2
            ;;
    esac
done

case "$MODE" in
    --device)
        PLATFORM="device"
        SDK="iphoneos"
        DESTINATION="generic/platform=iOS"
        ;;
    --simulator)
        PLATFORM="simulator"
        SDK="iphonesimulator"
        DESTINATION="generic/platform=iOS Simulator"
        ;;
esac

PREFIX_ROOT="$DEPS_ROOT/$PLATFORM"
SDL_PREFIX="$PREFIX_ROOT/sdl2"
FREETYPE_PREFIX="$PREFIX_ROOT/freetype"
SMOKE_BUILD="$ROOT/build-ios-smoke-$PLATFORM"
APP_BUILD="$ROOT/build-ios-app-$PLATFORM"

fetch_archive() {
    local url="$1"
    local expected_sha="$2"
    local archive="$3"

    if [[ ! -f "$archive" ]]; then
        curl -fL --retry 3 --retry-delay 2 "$url" -o "$archive"
    fi

    local actual_sha
    actual_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
    if [[ "$actual_sha" != "$expected_sha" ]]; then
        echo "Checksum mismatch for $archive" >&2
        echo "Expected: $expected_sha" >&2
        echo "Actual:   $actual_sha" >&2
        exit 1
    fi
}

extract_archive() {
    local archive="$1"
    local destination="$2"
    local marker="$3"

    if [[ -f "$destination/.banjopad-source" ]] &&
       [[ "$(cat "$destination/.banjopad-source")" == "$marker" ]]; then
        return
    fi

    rm -rf "$destination"
    mkdir -p "$destination"
    tar -xf "$archive" -C "$destination" --strip-components=1
    printf '%s\n' "$marker" > "$destination/.banjopad-source"
}

mkdir -p "$DOWNLOAD_ROOT" "$SOURCE_ROOT" "$PREFIX_ROOT"

SDL_ARCHIVE="$DOWNLOAD_ROOT/SDL2-$SDL_VERSION.tar.gz"
FREETYPE_ARCHIVE="$DOWNLOAD_ROOT/freetype-$FREETYPE_VERSION.tar.xz"

fetch_archive \
    "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VERSION/SDL2-$SDL_VERSION.tar.gz" \
    "$SDL_SHA256" \
    "$SDL_ARCHIVE"
fetch_archive \
    "https://downloads.sourceforge.net/freetype/freetype-$FREETYPE_VERSION.tar.xz" \
    "$FREETYPE_SHA256" \
    "$FREETYPE_ARCHIVE"

extract_archive "$SDL_ARCHIVE" "$SOURCE_ROOT/SDL2-$SDL_VERSION" "SDL2-$SDL_VERSION"
extract_archive "$FREETYPE_ARCHIVE" "$SOURCE_ROOT/freetype-$FREETYPE_VERSION" "freetype-$FREETYPE_VERSION"

if [[ ! -f "$SDL_PREFIX/lib/libSDL2.a" ]]; then
    cmake \
        -S "$SOURCE_ROOT/SDL2-$SDL_VERSION" \
        -B "$DEPS_ROOT/build-$PLATFORM-sdl2" \
        -G Xcode \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$SDK" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_INSTALL_PREFIX="$SDL_PREFIX" \
        -DSDL_SHARED=OFF \
        -DSDL_STATIC=ON \
        -DSDL_TEST=OFF \
        -DSDL_TESTS=OFF
    cmake --build "$DEPS_ROOT/build-$PLATFORM-sdl2" \
        --config Release \
        --target install \
        -- -destination "$DESTINATION" CODE_SIGNING_ALLOWED=NO
fi

if [[ ! -f "$FREETYPE_PREFIX/lib/libfreetype.a" ]]; then
    cmake \
        -S "$SOURCE_ROOT/freetype-$FREETYPE_VERSION" \
        -B "$DEPS_ROOT/build-$PLATFORM-freetype" \
        -G Xcode \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$SDK" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_INSTALL_PREFIX="$FREETYPE_PREFIX" \
        -DBUILD_SHARED_LIBS=OFF \
        -DFT_DISABLE_ZLIB=TRUE \
        -DFT_DISABLE_BZIP2=TRUE \
        -DFT_DISABLE_PNG=TRUE \
        -DFT_DISABLE_HARFBUZZ=TRUE \
        -DFT_DISABLE_BROTLI=TRUE
    cmake --build "$DEPS_ROOT/build-$PLATFORM-freetype" \
        --config Release \
        --target install \
        -- -destination "$DESTINATION" CODE_SIGNING_ALLOWED=NO
fi

if [[ "$PRODUCT" == "stub" ]]; then
    METAL_COMPILER="$(xcrun -f metal)"
    METALLIB_COMPILER="$(dirname "$METAL_COMPILER")/metallib"

    cmake \
        -S "$ROOT/sources/banjo" \
        -B "$APP_BUILD" \
        -G Xcode \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$SDK" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_PREFIX_PATH="$SDL_PREFIX;$FREETYPE_PREFIX" \
        -DSDL2_DIR="$SDL_PREFIX/lib/cmake/SDL2" \
        -DFreetype_DIR="$FREETYPE_PREFIX/lib/cmake/freetype" \
        -DBANJOPAD_IOS_DIR="$ROOT/ios/app" \
        -DBANJO_MOBILE_RENDERER_STUB=ON \
        -DDXC_PATH="$ROOT/sources/banjo/lib/rt64/src/contrib/dxc/bin/arm64/dxc-macos" \
        -DSPIRV_CROSS_MSL_PATH="$ROOT/build-host/bin/spirv_cross_msl" \
        -DFILE_TO_C_PATH="$ROOT/build-host/bin/file_to_c" \
        -DRT64_METAL_COMPILER_COMMAND="$METAL_COMPILER" \
        -DRT64_METALLIB_COMMAND="$METALLIB_COMPILER"

    set -- cmake --build "$APP_BUILD" \
        --config "$CONFIG" \
        --target BanjoRecompiled \
        -- -destination "$DESTINATION"
    if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
        set -- "$@" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
    fi
    "$@"

    echo
    echo "Built Phase 3 stub app:"
    echo "  $APP_BUILD/$CONFIG/BanjoRecompiled.app"
    exit
fi

if [[ "$PLATFORM" == "device" ]]; then
    PLUME_ARCHIVE="$ROOT/build-ios-rt64-device/rt64/src/contrib/plume/Release-iphoneos/libplume.a"
else
    PLUME_ARCHIVE="$ROOT/build-ios-rt64-simulator/rt64/src/contrib/plume/Release-iphonesimulator/libplume.a"
fi

if [[ ! -f "$PLUME_ARCHIVE" ]]; then
    echo "Missing Phase 1 plume archive: $PLUME_ARCHIVE" >&2
    exit 1
fi

cmake \
    -S "$ROOT/ios/smoke" \
    -B "$SMOKE_BUILD" \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$SDK" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_PREFIX_PATH="$SDL_PREFIX" \
    -DSDL2_DIR="$SDL_PREFIX/lib/cmake/SDL2" \
    -DDEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" \
    -DPLUME_ARCHIVE="$PLUME_ARCHIVE" \
    -DPLUME_INCLUDE_DIR="$ROOT/sources/banjo/lib/rt64/src/contrib/plume"

set -- cmake --build "$SMOKE_BUILD" \
    --config Release \
    --target BanjoPadMetalSmoke \
    -- -destination "$DESTINATION"
if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    set -- "$@" CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
fi
"$@"

echo
echo "Built Phase 2 smoke app:"
if [[ "$PLATFORM" == "device" ]]; then
    echo "  $SMOKE_BUILD/Release-iphoneos/BanjoPadMetalSmoke.app"
else
    echo "  $SMOKE_BUILD/Release-iphonesimulator/BanjoPadMetalSmoke.app"
fi
