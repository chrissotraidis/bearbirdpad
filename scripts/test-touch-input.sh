#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${TMPDIR:-/tmp}/banjopad-touch-input-shim-test"

xcrun --sdk macosx clang++ \
    -std=c++20 \
    -Wall \
    -Wextra \
    -Werror \
    -pthread \
    -I"$ROOT/ios/app" \
    "$ROOT/tests/touch_input_shim_test.cpp" \
    "$ROOT/ios/app/TouchInputShim.cpp" \
    -o "$OUTPUT"

"$OUTPUT"
echo "Touch input shim tests passed."
