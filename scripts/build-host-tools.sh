#!/bin/sh

set -eu

jobs=${CMAKE_BUILD_PARALLEL_LEVEL:-}
if [ -z "$jobs" ]; then
    jobs=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
fi
case "$jobs" in
    ''|0*|*[!0-9]*)
        echo "Host-tool job limit must be a positive integer without leading zeros." >&2
        exit 1
        ;;
esac

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_root="$repo_root/sources/banjo"
build_root="$repo_root/build-host"
superbuild="$repo_root/cmake/host-tools"

if [ ! -d "$source_root/lib/N64ModernRuntime/N64Recomp" ] ||
    [ ! -d "$source_root/lib/rt64" ]; then
    echo "Pinned sources are missing. Run scripts/fetch-sources.sh first." >&2
    exit 1
fi

cmake \
    -S "$superbuild" \
    -B "$build_root" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBEARBIRDPAD_SOURCE_ROOT="$source_root"

cmake --build "$build_root" \
    --target N64RecompCLI RSPRecomp file_to_c spirv_cross_msl rom_xxh3 \
    --parallel "$jobs"

for tool in N64Recomp RSPRecomp file_to_c spirv_cross_msl rom_xxh3; do
    tool_path="$build_root/bin/$tool"
    if [ ! -x "$tool_path" ]; then
        echo "Host tool was not produced: $tool_path" >&2
        exit 1
    fi
    file "$tool_path"
done

echo "Host tools are ready at $build_root/bin"
