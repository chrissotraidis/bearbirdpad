# Status — updated 2026-07-28, iteration 10

Phase: 3 — full app cross-compiles and boots with the renderer stub

Done this iteration: completed the automatable Phase 2 Metal smoke-harness work and advanced the physical-only acceptance checks to `HUMAN-VERIFY`. Evidence:

- `scripts/build-ios.sh` now checksum-pins and builds static SDL2 2.32.10 and FreeType 2.13.3 for arm64 `iphoneos` and `iphonesimulator`, then builds the isolated SDL/UIKit + plume-Metal harness in `ios/smoke/`.
- `scripts/build-ios.sh --simulator` and `scripts/build-ios.sh --device` both completed with `** BUILD SUCCEEDED **`; the device executable is arm64 Mach-O with `LC_BUILD_VERSION platform IOS`, `minos 16.0`.
- The smoke harness obtains both `info.uikit.window` and the SDL Metal layer, creates a three-texture plume swapchain, and runs acquire → plume clear → present. An assertion immediately before acquisition enforces that `nextDrawable` is never reached while backgrounded.
- Installed and launched `com.chrissotraidis.banjopad.smoke` on the booted iPad Pro 11-inch (M4), iOS 18.5 Simulator. The observed screen was a landscape animated blue/teal clear, and the console reported `BANJOPAD_SMOKE ready: device=Apple iOS simulator GPU`, `2420x1668`, three textures, 60 Hz, and continuing frame counts.
- Ran 20 Settings-app foreground/background cycles. Every cycle logged `background: drawable acquisition disabled`, `foreground: drawable acquisition enabled`, and a successful swapchain resize; rendering resumed beyond 7,000 frames with no crash or assertion.
- Rebuilt and relaunched after adding indirect-input support; the prior UIKit mouse-support warning disappeared. The remaining SDL UIKit appearance-transition diagnostics did not interrupt rendering.
- `xcrun devicectl list devices` reported `No devices found`, so no physical-device result or Instruments trace is claimed.

Next goal: implement the smallest Phase 3 slice: port the existing Android `banjo_recomp_main` split and null renderer behind mobile-only gates, add the iOS entry/path files, and get the complete target through its first arm64 iOS compile.

Blockers: none. Physical-device access is unavailable locally but does not block the next compile-focused goal.

ref/ additions: verified Banjo-Kazooie NTSC-U v1.0 retail dump (local-only and gitignored) — Phase 0 build/runtime input.

HUMAN-VERIFY queue:

- Phase 2 physical iPad present/lifecycle/trace — connect an iPad running iPadOS 16 or newer; run `DEVELOPMENT_TEAM=<team-id> scripts/build-ios.sh --device`; install `build-ios-smoke-device/Release-iphoneos/BanjoPadMetalSmoke.app` with Xcode or `xcrun devicectl device install app`; confirm the animated blue/teal clear remains landscape; perform 20 Home/app background-foreground cycles and confirm the app neither crashes nor receives a GPU-watchdog kill; record a Metal System Trace showing steady present cadence; confirm the console logs drawable acquisition disabled throughout every background interval and contains no assertion failure.

Deviations from plan: 2026-07-28 — the plan inherited BanjoRecomp's incorrect `1fe163...` decompressed-output SHA-1; that is the normalized retail ROM's SHA-1. The pinned bk-decomp target and generated output both use `1fb13cad402518d3ae9a8dc4b52c5c54b2a4adc7`, so the preparation gate and docs now use the verified generated hash. 2026-07-28 — bk-decomp's pinned n64splat submodule appears worktree-dirty immediately after checkout because upstream tracks one CRLF file while declaring `text eol=lf`; the diff is line-ending-only and no source logic was changed. 2026-07-28 — Xcode 26.6 downloaded Metal Toolchain 17F109 but `xcrun metal` could not mount it, so Phase 0 used the compiler and metallib binaries from the locally mounted signed toolchain through configurable CMake cache variables. 2026-07-28 — Homebrew's SDL2 compatibility library loads SDL3 dynamically, which CMake BundleUtilities cannot discover from Mach-O dependencies; the macOS bundle patch now copies the discovered SDL3 runtime explicitly. 2026-07-28 — plume is a separately pinned nested Git tree, so its UIKit patch lives in `patches/plume/` and `fetch-sources.sh` applies that series directly instead of pretending nested-source edits belong to RT64's parent worktree. 2026-07-28 — Savannah's FreeType download endpoint repeatedly returned HTTP 502 while SourceForge's official 2.13.3 mirror supplied the same release archive and published SHA-256; the build script uses the verified SourceForge URL.
