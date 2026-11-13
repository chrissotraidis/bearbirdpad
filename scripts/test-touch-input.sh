#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="${TMPDIR:-/tmp}/bearbirdpad-touch-input-shim-test"

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

VISIBILITY_OUTPUT="${TMPDIR:-/tmp}/bearbirdpad-touch-visibility-test"
xcrun --sdk macosx clang++ \
    -std=c++20 \
    -Wall \
    -Wextra \
    -Werror \
    -I"$ROOT/ios/app" \
    "$ROOT/tests/touch_visibility_test.cpp" \
    -o "$VISIBILITY_OUTPUT"
"$VISIBILITY_OUTPUT"
