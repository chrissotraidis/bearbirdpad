#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_root="$repo_root/sources/banjo"
banjo_url="https://github.com/BanjoRecomp/BanjoRecomp.git"
banjo_revision="c20314cd1bcaefff7bdbce257a25ebcc30cc1cdc"

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
            if git -C "$checkout" apply --reverse --check "$patch" >/dev/null 2>&1; then
                echo "Already applied: ${patch#"$repo_root/"}"
            else
                git -C "$checkout" apply --check "$patch"
                git -C "$checkout" apply "$patch"
                echo "Applied: ${patch#"$repo_root/"}"
            fi
        done
}

mkdir -p "$repo_root/sources"

if [ ! -d "$source_root/.git" ]; then
    git clone --filter=blob:none --no-checkout "$banjo_url" "$source_root"
fi

git -C "$source_root" fetch --depth=1 origin "$banjo_revision"
git -C "$source_root" checkout --detach "$banjo_revision"
git -C "$source_root" submodule sync --recursive
git -C "$source_root" submodule update --init --recursive

assert_revision "$source_root" "$banjo_revision" "BanjoRecomp"
assert_revision "$source_root/lib/N64ModernRuntime" "ca568b6" "N64ModernRuntime"
assert_revision "$source_root/lib/N64ModernRuntime/N64Recomp" "2b6f056" "N64Recomp"
assert_revision "$source_root/lib/rt64" "6f1c2d9" "rt64"
assert_revision "$source_root/lib/rt64/src/contrib/plume" "d890ac8" "plume"
assert_revision "$source_root/lib/RecompFrontend" "d0d90ba" "RecompFrontend"
assert_revision "$source_root/lib/bk-decomp" "351ca15" "bk-decomp"
assert_revision "$source_root/BanjoRecompSyms" "6820055" "BanjoRecompSyms"

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

echo "Pinned sources are ready at $source_root"
