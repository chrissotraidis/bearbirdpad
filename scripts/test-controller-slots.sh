#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${TMPDIR:-/tmp}/bearbirdpad-controller-slots-test"

xcrun --sdk macosx clang++ \
    -std=c++20 \
    -Wall \
    -Wextra \
    -Werror \
    -I"$ROOT/ios/app" \
    "$ROOT/tests/controller_slots_test.cpp" \
    -o "$OUTPUT"

"$OUTPUT"
echo "Controller slot tests passed."
