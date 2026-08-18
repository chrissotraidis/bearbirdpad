#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
app_path=${1:-"$repo_root/build-ios-app-device/Release/BanjoRecompiled.app"}
output_path=${2:-"$repo_root/build/release/BearBirdPad-0.1.0-preview.2-unsigned.ipa"}

case "$output_path" in
    /*) ;;
    *) output_path="$PWD/$output_path" ;;
esac

package_root=$(mktemp -d)
trap 'rm -rf "$package_root"' EXIT HUP INT TERM
mkdir -p "$package_root/Payload" "$(dirname "$output_path")"
ditto "$app_path" "$package_root/Payload/$(basename "$app_path")"

"$repo_root/scripts/package-audit.sh" "$package_root/Payload/$(basename "$app_path")"

for notice in LICENSE RIGHTS_AND_LICENSES.md THIRD_PARTY_NOTICES.md; do
    if [ ! -f "$repo_root/$notice" ]; then
        echo "Required release notice is missing: $notice" >&2
        exit 1
    fi
    cp "$repo_root/$notice" "$package_root/$notice"
done

licenses_dir="$package_root/ThirdPartyLicenses"
license_count=0
mkdir -p "$licenses_dir"
while IFS= read -r license_file; do
    relative=${license_file#"$repo_root/"}
    destination="$licenses_dir/$relative"
    mkdir -p "$(dirname "$destination")"
    cp "$license_file" "$destination"
    license_count=$((license_count + 1))
done <<EOF
$(find "$repo_root/sources/banjo" "$repo_root/build-ios-deps/sources" -type f \
    \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname 'NOTICE*' \) \
    -print | LC_ALL=C sort)
EOF

if [ "$license_count" -eq 0 ]; then
    echo "No third-party license files were found for packaging" >&2
    exit 1
fi

export TZ=UTC
find "$package_root" -exec touch -h -t 200101010000 {} +
archive_path="$package_root/BearBirdPad.ipa"

(
    cd "$package_root"
    find LICENSE RIGHTS_AND_LICENSES.md THIRD_PARTY_NOTICES.md ThirdPartyLicenses Payload -print |
        LC_ALL=C sort |
        COPYFILE_DISABLE=1 zip -q -X "$archive_path" -@
)

unzip -tq "$archive_path" >/dev/null
entries=$(unzip -Z1 "$archive_path")
for notice in LICENSE RIGHTS_AND_LICENSES.md THIRD_PARTY_NOTICES.md; do
    if ! printf '%s\n' "$entries" | grep -Fxq "$notice"; then
        echo "IPA licensing notice is missing: $notice" >&2
        exit 1
    fi
done
if ! printf '%s\n' "$entries" | grep -Fq 'ThirdPartyLicenses/'; then
    echo "IPA contains no third-party license files" >&2
    exit 1
fi
mv -f "$archive_path" "$output_path"
sha256=$(shasum -a 256 "$output_path" | awk '{print $1}')
size=$(wc -c < "$output_path" | tr -d ' ')

echo "Packaged iOS archive:"
echo "  $output_path"
echo "  size: $size bytes"
echo "  sha256: $sha256"
echo "  third-party licenses: $license_count"
