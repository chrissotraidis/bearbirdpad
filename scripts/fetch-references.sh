#!/bin/sh

set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
reference_root="$repo_root/ref"

clone_reference() {
    name=$1
    url=$2
    recursive=$3
    checkout="$reference_root/$name"

    if [ ! -d "$checkout/.git" ]; then
        if [ "$recursive" = "yes" ]; then
            git clone --filter=blob:none --recurse-submodules "$url" "$checkout"
        else
            git clone --filter=blob:none "$url" "$checkout"
        fi
    fi

    git -C "$checkout" remote set-url --push origin DISABLED
    if [ "$recursive" = "yes" ]; then
        git -C "$checkout" submodule foreach --quiet --recursive \
            'if git remote get-url origin >/dev/null 2>&1; then git remote set-url --push origin DISABLED; fi'
    fi

    printf '%s\t%s\n' "$name" "$(git -C "$checkout" rev-parse HEAD)"
}

mkdir -p "$reference_root"

clone_reference BanjoRecomp-Android \
    https://github.com/AurelioB/BanjoRecomp-Android.git yes
clone_reference N64Recomp \
    https://github.com/N64Recomp/N64Recomp.git yes
clone_reference N64ModernRuntime \
    https://github.com/N64Recomp/N64ModernRuntime.git yes
clone_reference rt64 \
    https://github.com/rt64/rt64.git yes

if [ -d /Users/chrissotraidis/GitHub/harkinianpad/.git ]; then
    printf '%s\t%s\n' HarkinianPad \
        "$(git -C /Users/chrissotraidis/GitHub/harkinianpad rev-parse HEAD)"
fi
