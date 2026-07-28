# Status — updated 2026-07-28, iteration 8

Phase: 1 — plume + RT64 compile for the iOS SDK

Done this iteration: completed the Phase 0 macOS baseline with the user's full retail dump. Evidence:

- `scripts/prepare-generated.sh 'ref/Banjo-Kazooie (U) [!].z64'` → retail XXH3-64 `1B67585D56E07F8C`, decompressed SHA-1 `1fb13cad402518d3ae9a8dc4b52c5c54b2a4adc7`, 8,500 functions, 169 game source files, and `rsp/n_aspMain.cpp`.
- `cmake --build build-macos --target BanjoRecompiled` → signed arm64 `BanjoRecompiled.app`; CMake BundleUtilities validated SDL2, SDL3, FreeType, and libpng, and `codesign --verify --deep --strict` passed.
- `BanjoRecompiled --rom <retail-dump> --auto-start` → the built-in importer normalized the dump to big-endian `bk.n64.us.1.0.z64`, created the normal config JSONs and save file, opened the required 48 kHz SDL audio device, rendered the Banjo-Kazooie `PRESS START` title screen, and stayed alive for 14 minutes before operator shutdown.
- The first immediate-start run exposed a null VI-mode race. `patches/nmr/001-initialize-vi-before-thread.patch` initializes the dummy VI state before starting the VI thread; the same launch then completed without a new crash report.
- `git ls-files` prohibited-content scan → no ROM, generated recompilation source, or RSP output is tracked.

Next goal: build the Phase 1 RT64-only harness for `arm64-iphoneos`, including iOS plume windowing and iPhoneOS Metal shader blobs.

Blockers: none.

ref/ additions: verified Banjo-Kazooie NTSC-U v1.0 retail dump (local-only and gitignored) — Phase 0 build/runtime input.

HUMAN-VERIFY queue: none.

Deviations from plan: 2026-07-28 — the plan inherited BanjoRecomp's incorrect `1fe163...` decompressed-output SHA-1; that is the normalized retail ROM's SHA-1. The pinned bk-decomp target and generated output both use `1fb13cad402518d3ae9a8dc4b52c5c54b2a4adc7`, so the preparation gate and docs now use the verified generated hash. 2026-07-28 — bk-decomp's pinned n64splat submodule appears worktree-dirty immediately after checkout because upstream tracks one CRLF file while declaring `text eol=lf`; the diff is line-ending-only and no source logic was changed. 2026-07-28 — Xcode 26.6 downloaded Metal Toolchain 17F109 but `xcrun metal` could not mount it, so Phase 0 used the compiler and metallib binaries from the locally mounted signed toolchain through configurable CMake cache variables. 2026-07-28 — Homebrew's SDL2 compatibility library loads SDL3 dynamically, which CMake BundleUtilities cannot discover from Mach-O dependencies; the macOS bundle patch now copies the discovered SDL3 runtime explicitly.
