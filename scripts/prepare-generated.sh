#!/bin/sh

set -eu

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path-to-retail-rom>" >&2
    exit 2
fi

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_root="$repo_root/sources/banjo"
build_root="$repo_root/build-host"
rom_path=$1
decompressed_rom="$source_root/banjo.us.v10.decompressed.z64"
expected_retail_hash="1B67585D56E07F8C"
expected_retail_size="16777216"
expected_decompressed_sha1="1fb13cad402518d3ae9a8dc4b52c5c54b2a4adc7"
compressor_source="$source_root/lib/bk-decomp/tools/bk_rom_compressor"
compressor_build="$build_root/bk-rom-compressor"
compressor="$compressor_build/release/bk_rom_decompress"

if [ ! -f "$rom_path" ]; then
    echo "Retail ROM not found: $rom_path" >&2
    exit 2
fi

retail_size=$(wc -c < "$rom_path" | tr -d '[:space:]')
if [ "$retail_size" != "$expected_retail_size" ]; then
    echo "Retail ROM size mismatch: expected $expected_retail_size bytes (16 MiB), found $retail_size" >&2
    if [ "$retail_size" = "8388608" ]; then
        echo "The file is exactly half the required size and appears truncated." >&2
    fi
    echo "Do not pad the file: the missing range contains game data. Re-dump the complete cartridge image." >&2
    exit 1
fi

if [ ! -x "$build_root/bin/rom_xxh3" ] ||
    [ ! -x "$build_root/bin/N64Recomp" ] ||
    [ ! -x "$build_root/bin/RSPRecomp" ] ||
    [ ! -x "$build_root/bin/file_to_c" ]; then
    "$repo_root/scripts/build-host-tools.sh"
fi

retail_hash=$("$build_root/bin/rom_xxh3" "$rom_path")
if [ "$retail_hash" != "$expected_retail_hash" ]; then
    echo "Retail ROM hash mismatch: expected $expected_retail_hash, found $retail_hash" >&2
    exit 1
fi
echo "Retail ROM XXH3-64 verified: $retail_hash"

decompressed_sha1=""
if [ -f "$decompressed_rom" ]; then
    decompressed_sha1=$(shasum -a 1 "$decompressed_rom" | awk '{print $1}')
fi

if [ "$decompressed_sha1" != "$expected_decompressed_sha1" ]; then
    cargo build \
        --release \
        --locked \
        --manifest-path "$compressor_source/Cargo.toml" \
        --target-dir "$compressor_build" \
        --bin bk_rom_decompress

    temporary_rom=$(mktemp "$source_root/.banjo-decompressed.XXXXXX")
    trap 'rm -f "$temporary_rom"' EXIT HUP INT TERM
    "$compressor" "$rom_path" "$temporary_rom"

    decompressed_sha1=$(shasum -a 1 "$temporary_rom" | awk '{print $1}')
    if [ "$decompressed_sha1" != "$expected_decompressed_sha1" ]; then
        echo "Decompressed ROM sha1 mismatch: expected $expected_decompressed_sha1, found $decompressed_sha1" >&2
        exit 1
    fi

    mv "$temporary_rom" "$decompressed_rom"
    trap - EXIT HUP INT TERM
fi
echo "Decompressed ROM sha1 verified: $decompressed_sha1"

install -m 755 "$build_root/bin/N64Recomp" "$source_root/N64Recomp"
install -m 755 "$build_root/bin/RSPRecomp" "$source_root/RSPRecomp"

have_game_sources=false
if [ -d "$source_root/RecompiledFuncs" ] &&
    find "$source_root/RecompiledFuncs" -type f \( -name '*.c' -o -name '*.cpp' \) -print -quit |
        grep -q .; then
    have_game_sources=true
fi

if [ "$have_game_sources" = true ] &&
    [ -s "$source_root/rsp/n_aspMain.cpp" ]; then
    echo "Generated AOT game and RSP sources are already present."
else
    (
        cd "$source_root"
        ./N64Recomp banjo.us.rev0.toml
        ./RSPRecomp n_aspMain.us.rev0.toml
    )
fi

have_patch_sources=true
for generated_file in \
    "$source_root/RecompiledPatches/patches.c" \
    "$source_root/RecompiledPatches/patches_bin.c" \
    "$source_root/RecompiledPatches/patches_bin.h" \
    "$source_root/RecompiledPatches/recomp_overlays.inl" \
    "$source_root/RecompiledPatches/funcs.h" \
    "$source_root/patches/patches.bin"; do
    if [ ! -s "$generated_file" ]; then
        have_patch_sources=false
        break
    fi
done

if [ "$have_patch_sources" = true ]; then
    echo "Generated patch sources are already present."
else
    llvm_prefix=$(brew --prefix llvm 2>/dev/null || true)
    lld_prefix=$(brew --prefix lld 2>/dev/null || true)
    patch_cc="$llvm_prefix/bin/clang"
    patch_ld="$lld_prefix/bin/ld.lld"

    if [ ! -x "$patch_cc" ] || [ ! -x "$patch_ld" ]; then
        echo "The patch generator requires Homebrew LLVM and lld." >&2
        echo "Install them with: brew install llvm lld" >&2
        exit 1
    fi

    make -C "$source_root/patches" CC="$patch_cc" LD="$patch_ld"
    (
        cd "$source_root"
        ./N64Recomp patches.toml
    )
    "$build_root/bin/file_to_c" \
        "$source_root/patches/patches.bin" \
        bk_patches_bin \
        "$source_root/RecompiledPatches/patches_bin.c" \
        "$source_root/RecompiledPatches/patches_bin.h"
fi

game_source_count=$(find "$source_root/RecompiledFuncs" \
    -type f \( -name '*.c' -o -name '*.cpp' \) | wc -l | tr -d ' ')
if [ "$game_source_count" -eq 0 ] ||
    [ ! -s "$source_root/rsp/n_aspMain.cpp" ]; then
    echo "Generated source verification failed" >&2
    exit 1
fi

for generated_file in \
    "$source_root/RecompiledPatches/patches.c" \
    "$source_root/RecompiledPatches/patches_bin.c" \
    "$source_root/RecompiledPatches/patches_bin.h" \
    "$source_root/RecompiledPatches/recomp_overlays.inl" \
    "$source_root/RecompiledPatches/funcs.h" \
    "$source_root/patches/patches.bin"; do
    if [ ! -s "$generated_file" ]; then
        echo "Generated patch source verification failed: $generated_file" >&2
        exit 1
    fi
done

echo "Generated sources are ready: $game_source_count game files, RSP, and patches"
