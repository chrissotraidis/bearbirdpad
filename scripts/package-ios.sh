#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_path=${1:-"$repo_root/build-ios-app-device/Release/BanjoRecompiled.app"}
output_path=${2:-"$repo_root/build/release/BanjoPad-0.1.0-unsigned.ipa"}

case "$output_path" in
    /*) ;;
    *) output_path="$PWD/$output_path" ;;
esac

"$repo_root/scripts/package-audit.sh" "$app_path"

package_root=$(mktemp -d)
trap 'rm -rf "$package_root"' EXIT HUP INT TERM
mkdir -p "$package_root/Payload" "$(dirname "$output_path")"
ditto "$app_path" "$package_root/Payload/$(basename "$app_path")"

(
    cd "$package_root"
    COPYFILE_DISABLE=1 zip -q -r -X "$output_path" Payload
)

unzip -tq "$output_path" >/dev/null
sha256=$(shasum -a 256 "$output_path" | awk '{print $1}')
size=$(du -h "$output_path" | awk '{print $1}')

echo "Packaged iOS archive:"
echo "  $output_path"
echo "  size: $size"
echo "  sha256: $sha256"
