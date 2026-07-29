#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_root="$repo_root/sources/banjo"
banjo_url="https://github.com/BanjoRecomp/BanjoRecomp.git"
banjo_revision="c20314cd1bcaefff7bdbce257a25ebcc30cc1cdc"
banjo_syms_revision="6820055"
nmr_revision="ca568b6"
n64recomp_revision="2b6f056"
rt64_revision="6f1c2d9"
plume_revision="d890ac8"
frontend_revision="d0d90ba"
bk_decomp_revision="351ca15"
patch_state="$source_root/.banjopad-patch-state"
using_patch_state=false

assert_revision() {
    checkout=$1
    expected=$2
    label=$3

    if [ ! -d "$checkout" ]; then
        echo "Missing pinned checkout for $label: $checkout" >&2
        exit 1
    fi

    actual=$(git -C "$checkout" rev-parse HEAD)
    case "$actual" in
        "$expected"*) ;;
        *)
            echo "$label revision mismatch: expected $expected, found $actual" >&2
            exit 1
            ;;
    esac
}

disable_pushes() {
    checkout=$1
    if git -C "$checkout" remote get-url origin >/dev/null 2>&1; then
        git -C "$checkout" remote set-url --push origin DISABLED
    fi
}

apply_series() {
    tree=$1
    checkout=$2
    patch_dir="$repo_root/patches/$tree"

    [ -d "$patch_dir" ] || return 0

    find "$patch_dir" -maxdepth 1 -type f -name '*.patch' -print |
        LC_ALL=C sort |
        while IFS= read -r patch; do
            relative_patch=${patch#"$repo_root/"}
            patch_sha=$(shasum -a 256 "$patch" | awk '{print $1}')
            state_line="$patch_sha  $relative_patch"

            if [ "$using_patch_state" = true ]; then
                if grep -Fqx "$state_line" "$patch_state"; then
                    echo "Already applied (state): $relative_patch"
                    continue
                fi
                if grep -Fq "  $relative_patch" "$patch_state"; then
                    if git -C "$checkout" apply --reverse --check "$patch" >/dev/null 2>&1; then
                        echo "Already applied (verified patch correction): $relative_patch"
                        continue
                    fi
                    echo "Applied patch changed in place: $relative_patch" >&2
                    echo "The updated patch does not match the cached source tree; recreate sources/ to replay it." >&2
                    exit 1
                fi
            fi

            if git -C "$checkout" apply --reverse --check "$patch" >/dev/null 2>&1; then
                echo "Already applied: $relative_patch"
            else
                git -C "$checkout" apply --check "$patch"
                git -C "$checkout" apply "$patch"
                echo "Applied: $relative_patch"
            fi
        done
}

mkdir -p "$repo_root/sources"

if [ ! -d "$source_root/.git" ]; then
    git clone --filter=blob:none --no-checkout "$banjo_url" "$source_root"
fi

if [ -f "$patch_state" ]; then
    if grep -Fqx "banjo_revision $banjo_revision" "$patch_state"; then
        using_patch_state=true
        echo "Using verified cached patch state: ${patch_state#"$repo_root/"}"
    else
        echo "Pinned revision changed for an existing patched source cache." >&2
        echo "Recreate sources/ to replay the new revision from a clean tree." >&2
        exit 1
    fi
else
    git -C "$source_root" fetch --depth=1 origin "$banjo_revision"
    git -C "$source_root" checkout --detach "$banjo_revision"
    git -C "$source_root" submodule sync --recursive
    git -C "$source_root" submodule update --init --recursive
fi

assert_revision "$source_root" "$banjo_revision" "BanjoRecomp"
assert_revision "$source_root/lib/N64ModernRuntime" "$nmr_revision" "N64ModernRuntime"
assert_revision "$source_root/lib/N64ModernRuntime/N64Recomp" "$n64recomp_revision" "N64Recomp"
assert_revision "$source_root/lib/rt64" "$rt64_revision" "rt64"
assert_revision "$source_root/lib/rt64/src/contrib/plume" "$plume_revision" "plume"
assert_revision "$source_root/lib/RecompFrontend" "$frontend_revision" "RecompFrontend"
assert_revision "$source_root/lib/bk-decomp" "$bk_decomp_revision" "bk-decomp"
assert_revision "$source_root/BanjoRecompSyms" "$banjo_syms_revision" "BanjoRecompSyms"

disable_pushes "$source_root"
git -C "$source_root" submodule foreach --quiet --recursive \
    'if git remote get-url origin >/dev/null 2>&1; then git remote set-url --push origin DISABLED; fi'

apply_series banjo "$source_root"
apply_series nmr "$source_root/lib/N64ModernRuntime"
apply_series sljit "$source_root/lib/N64ModernRuntime/N64Recomp/lib/sljit"
apply_series rt64 "$source_root/lib/rt64"
apply_series hlslpp "$source_root/lib/rt64/src/contrib/hlslpp"
apply_series plume "$source_root/lib/rt64/src/contrib/plume"
apply_series nfd "$source_root/lib/rt64/src/contrib/nativefiledialog-extended"
apply_series frontend "$source_root/lib/RecompFrontend"

{
    echo "banjo_revision $banjo_revision"
    find "$repo_root/patches" -type f -name '*.patch' -print |
        LC_ALL=C sort |
        while IFS= read -r patch; do
            relative_patch=${patch#"$repo_root/"}
            patch_sha=$(shasum -a 256 "$patch" | awk '{print $1}')
            echo "$patch_sha  $relative_patch"
        done
} > "$patch_state"

echo "Pinned sources are ready at $source_root"
