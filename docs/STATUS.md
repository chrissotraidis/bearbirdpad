# Status — updated 2026-07-28, iteration 9

Phase: 2 — Metal smoke harness on device

Done this iteration: completed the Phase 1 iOS renderer cross-compile. Evidence:

- The thin `ios/cmake/CMakeLists.txt` harness configured with `CMAKE_SYSTEM_NAME=iOS` for both `iphoneos` and `iphonesimulator`, using the pinned host DXC, `spirv_cross_msl`, and `file_to_c`.
- `cmake --build build-ios-rt64-device --config Release --target rt64` → arm64 `rt64.a` plus arm64 `libplume.a`; 56 iPhoneOS `.metallib` files and 56 embedded `*BlobMSL` C arrays were generated.
- `cmake --build build-ios-rt64-simulator --config Release --target rt64` → the same archive pair and all 56 shader blobs for arm64 Simulator.
- Representative `plume_uikit.o` load commands report `platform 2` / `minos 16.0` for device and `platform 7` / `minos 16.0` for Simulator; `nm -um` across both archive pairs found zero `NSWindow`, `NSScreen`, `IOService`, `IORegistry`, `IOKit`, or `AppKit` symbol hits.
- Representative device and Simulator metallibs passed `metallib --app-store-validate`; `file` recognized them as MetalLib executables.
- Clean temporary checkouts applied `patches/rt64/*.patch` and `patches/plume/*.patch` in order, and every patch also passed reverse-apply checks against the working source.
- `cmake --build build-macos --target BanjoRecompiled` rebuilt the shared code after the iOS changes; BundleUtilities verified the app and `codesign --verify --deep --strict` passed.

Next goal: build the minimal Phase 2 SDL/UIKit + plume-Metal smoke app and prove a clear/present loop in Simulator before the physical-device gate.

Blockers: none.

ref/ additions: verified Banjo-Kazooie NTSC-U v1.0 retail dump (local-only and gitignored) — Phase 0 build/runtime input.

HUMAN-VERIFY queue: none.

Deviations from plan: 2026-07-28 — the plan inherited BanjoRecomp's incorrect `1fe163...` decompressed-output SHA-1; that is the normalized retail ROM's SHA-1. The pinned bk-decomp target and generated output both use `1fb13cad402518d3ae9a8dc4b52c5c54b2a4adc7`, so the preparation gate and docs now use the verified generated hash. 2026-07-28 — bk-decomp's pinned n64splat submodule appears worktree-dirty immediately after checkout because upstream tracks one CRLF file while declaring `text eol=lf`; the diff is line-ending-only and no source logic was changed. 2026-07-28 — Xcode 26.6 downloaded Metal Toolchain 17F109 but `xcrun metal` could not mount it, so Phase 0 used the compiler and metallib binaries from the locally mounted signed toolchain through configurable CMake cache variables. 2026-07-28 — Homebrew's SDL2 compatibility library loads SDL3 dynamically, which CMake BundleUtilities cannot discover from Mach-O dependencies; the macOS bundle patch now copies the discovered SDL3 runtime explicitly. 2026-07-28 — plume is a separately pinned nested Git tree, so its UIKit patch lives in `patches/plume/` and `fetch-sources.sh` applies that series directly instead of pretending nested-source edits belong to RT64's parent worktree.
