#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_path=${1:-"$repo_root/build-ios-app-device/Release/BanjoRecompiled.app"}
output_path=${2:-"$repo_root/build/release/BearBirdPad-0.1.0-unsigned.ipa"}

case "$output_path" in
    /*) ;;
    *) output_path="$PWD/$output_path" ;;
esac

"$repo_root/scripts/package-audit.sh" "$app_path"

package_root=$(mktemp -d)
trap 'rm -rf "$package_root"' EXIT HUP INT TERM
mkdir -p "$package_root/Payload" "$(dirname "$output_path")"
ditto "$app_path" "$package_root/Payload/$(basename "$app_path")"

export TZ=UTC
find "$package_root/Payload" -exec touch -h -t 200101010000 {} +
archive_path="$package_root/BearBirdPad.ipa"

(
    cd "$package_root"
    find Payload -print |
        LC_ALL=C sort |
        COPYFILE_DISABLE=1 zip -q -X "$archive_path" -@
)

unzip -tq "$archive_path" >/dev/null
mv -f "$archive_path" "$output_path"
sha256=$(shasum -a 256 "$output_path" | awk '{print $1}')
size=$(wc -c < "$output_path" | tr -d ' ')

echo "Packaged iOS archive:"
echo "  $output_path"
echo "  size: $size bytes"
echo "  sha256: $sha256"
