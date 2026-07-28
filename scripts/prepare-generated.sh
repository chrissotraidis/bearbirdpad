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
expected_decompressed_sha1="1fe1632098865f639e22c11b9a81ee8f29c75d7a"
compressor_source="$source_root/lib/bk-decomp/tools/bk_rom_compressor"
compressor_build="$build_root/bk-rom-compressor"
compressor="$compressor_build/release/bk_rom_decompress"

if [ ! -f "$rom_path" ]; then
    echo "Retail ROM not found: $rom_path" >&2
    exit 2
fi

if [ ! -x "$build_root/bin/rom_xxh3" ] ||
    [ ! -x "$build_root/bin/N64Recomp" ] ||
    [ ! -x "$build_root/bin/RSPRecomp" ]; then
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

game_source_count=$(find "$source_root/RecompiledFuncs" \
    -type f \( -name '*.c' -o -name '*.cpp' \) | wc -l | tr -d ' ')
if [ "$game_source_count" -eq 0 ] ||
    [ ! -s "$source_root/rsp/n_aspMain.cpp" ]; then
    echo "Generated source verification failed" >&2
    exit 1
fi

echo "Generated sources are ready: $game_source_count game files and rsp/n_aspMain.cpp"
