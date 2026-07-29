#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_path=${1:-"$repo_root/build-ios-app-device/Release/BanjoRecompiled.app"}
require_signed=${REQUIRE_SIGNED:-0}

if [ ! -d "$app_path" ]; then
    echo "App bundle not found: $app_path" >&2
    exit 2
fi

case "$require_signed" in
    0|1) ;;
    *)
        echo "REQUIRE_SIGNED must be 0 or 1" >&2
        exit 2
        ;;
esac

violations=$(mktemp)
trap 'rm -f "$violations"' EXIT HUP INT TERM

find "$app_path" -type f -print |
    LC_ALL=C sort |
    while IFS= read -r file; do
        relative=${file#"$app_path"/}
        lower=$(printf '%s' "$relative" | tr '[:upper:]' '[:lower:]')
        case "$lower" in
            *.z64|*.v64|*.n64|*recompiledfuncs*|*recompiledpatches*|*banjo.us*|*n_aspmain.cpp*)
                echo "Forbidden package path: $relative" >> "$violations"
                ;;
        esac

        sha1=$(shasum -a 1 "$file" | awk '{print $1}')
        case "$sha1" in
            1fe1632098865f639e22c11b9a81ee8f29c75d7a|1fb13cad402518d3ae9a8dc4b52c5c54b2a4adc7)
                echo "Known ROM digest in package: $relative ($sha1)" >> "$violations"
                ;;
        esac
    done

if find "$app_path" -type f ! -name BanjoRecompiled ! -name BanjoPadCIStub -exec \
    grep -IEl '1fe1632098865f639e22c11b9a81ee8f29c75d7a|1fb13cad402518d3ae9a8dc4b52c5c54b2a4adc7|RecompiledFuncs|RecompiledPatches|banjo\.us\.v10\.decompressed' {} + \
    >> "$violations"; then
    :
fi

if [ -s "$violations" ]; then
    echo "Package audit failed:" >&2
    sed 's/^/  /' "$violations" >&2
    exit 1
fi

if [ "$require_signed" = 1 ]; then
    codesign --verify --deep --strict --verbose=2 "$app_path"
    if [ ! -s "$app_path/embedded.mobileprovision" ]; then
        echo "Signed package is missing embedded.mobileprovision" >&2
        exit 1
    fi
fi

echo "Package audit passed: $app_path"
echo "  ROM files/digests: absent"
echo "  Generated-source paths/markers: absent"
if [ "$require_signed" = 1 ]; then
    echo "  Signature and provisioning profile: valid"
else
    echo "  Signature requirement: skipped (REQUIRE_SIGNED=0)"
fi
