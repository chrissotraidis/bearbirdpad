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
signature_info=$(mktemp)
profile_info=$(mktemp)
trap 'rm -f "$violations" "$signature_info" "$profile_info"' EXIT HUP INT TERM

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

find "$app_path" -type f ! -name BanjoRecompiled ! -name BanjoPadCIStub -exec \
    grep -IEl '1fe1632098865f639e22c11b9a81ee8f29c75d7a|1fb13cad402518d3ae9a8dc4b52c5c54b2a4adc7|RecompiledFuncs|RecompiledPatches|banjo\.us\.v10\.decompressed' {} + |
    LC_ALL=C sort |
    while IFS= read -r file; do
        relative=${file#"$app_path"/}
        echo "Forbidden package marker: $relative" >> "$violations"
    done

if [ -s "$violations" ]; then
    echo "Package audit failed:" >&2
    sed 's/^/  /' "$violations" >&2
    exit 1
fi

has_signature_material=0
if [ -d "$app_path/_CodeSignature" ] ||
   [ -f "$app_path/embedded.mobileprovision" ]; then
    has_signature_material=1
fi

if [ "$has_signature_material" = 1 ]; then
    if [ ! -d "$app_path/_CodeSignature" ] ||
       [ ! -s "$app_path/embedded.mobileprovision" ]; then
        echo "Package contains incomplete or stale signing material" >&2
        exit 1
    fi

    codesign --verify --deep --strict --verbose=2 "$app_path"
    codesign -d --verbose=4 "$app_path" 2> "$signature_info"

    signature=$(sed -n 's/^Signature=//p' "$signature_info")
    team_id=$(sed -n 's/^TeamIdentifier=//p' "$signature_info")
    if [ "$signature" = "adhoc" ] || [ -z "$team_id" ] || [ "$team_id" = "not set" ]; then
        echo "Signed package must use an Apple development/distribution identity, not an ad-hoc signature" >&2
        exit 1
    fi

    profile="$app_path/embedded.mobileprovision"
    if [ ! -s "$profile" ]; then
        echo "Signed package is missing embedded.mobileprovision" >&2
        exit 1
    fi
    if ! security cms -D -i "$profile" > "$profile_info" 2>/dev/null; then
        echo "Signed package has an invalid embedded.mobileprovision" >&2
        exit 1
    fi

    profile_team=$(/usr/libexec/PlistBuddy -c 'Print :TeamIdentifier:0' "$profile_info" 2>/dev/null || true)
    if [ -z "$profile_team" ] || [ "$profile_team" != "$team_id" ]; then
        echo "Signed package TeamIdentifier does not match embedded.mobileprovision" >&2
        exit 1
    fi
elif [ "$require_signed" = 1 ]; then
    echo "REQUIRE_SIGNED=1, but the app has no signature or provisioning profile" >&2
    exit 1
fi

echo "Package audit passed: $app_path"
echo "  ROM files/digests: absent"
echo "  Generated-source paths/markers: absent"
if [ "$has_signature_material" = 1 ]; then
    echo "  Non-ad-hoc signature and provisioning TeamIdentifier: valid"
else
    echo "  Signing material: absent"
fi
