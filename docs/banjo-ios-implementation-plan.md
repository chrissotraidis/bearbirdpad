# BanjoRecomp on iOS/iPadOS — Implementation Plan

Companion to [banjo-ios-feasibility.md](banjo-ios-feasibility.md) (read it first; this plan assumes its findings and does not re-argue them). Working project name: **banjopad**. Tree tags (`banjo:`, `nmr:`, `n64recomp:`, `rt64:`, `plume:`, `frontend:`, `android:`) and pinned revisions are the same as the feasibility document's table. All upstream file/line citations were verified at those pins on 2026-07-28; re-verify after any pin bump.

---

## 1. Summary

Build a native iPadOS/iOS app of Banjo: Recompiled on top of pinned BanjoRecomp `c20314c` and its submodules, following the architecture the Android port proved (SDL-owned window, platform document picker bridged into the existing flows, app-private path env-var seams, lifecycle pause gates) with the renderer swapped from plume-Vulkan to plume-Metal — the backend the shipped macOS build already uses in production, completed for iOS by adding a UIKit window helper, three `PLUME_IOS` API guards, an iOS CMake arm, and a two-line shader-toolchain retarget.

The shape of the approach:

- **AOT-only runtime.** The base game is fully ahead-of-time compiled; the mod system stays compiled in but code-mod loading is hard-disabled on iOS. No JIT entitlement, no pairing ritual, install-and-play. Texture packs (data-only `.rtz`) fully supported.
- **banjopad is the publication repository.** All upstream repos are read-only pinned build inputs; every change lives here as an ordered patch series. No pushes, branches, or PRs to any upstream (HarkinianPad's proven model).
- **Two-track bring-up**, exactly as the Android port did: Track A proves the app shell (paths, audio, input, lifecycle) under a renderer stub; Track B brings up plume-Metal-on-iOS from "compiles" to "first frame." They merge at the launcher-renders milestone.
- **Touch controls are new work** (no port of this stack has them) — a UIKit overlay injecting into the `ultramodern::input::callbacks_t::get_input` seam, with BK's analog-camera option driven by a right-half camera drag region.
- Primary target: iPad (M-series and A13+), landscape. iPhone supported at reduced scale. Floor: iOS 16.0, GPU family Apple3+.

---

## 2. Decisions

Every decision, the options considered, the choice, and why. D-numbers are referenced throughout the plan.

**D1 — JIT vs AOT: AOT-only, code mods disabled on iOS.**
Options: (a) AOT-only; (b) JIT via get-task-allow + StikDebug/SideStore ritual; (c) dual-mode.
Chosen: (a), with a cheap capability probe left in for diagnostics only.
Why: the base game needs no JIT (feasibility §1); code mods need *both* MAP_JIT and writable `__TEXT` for `patch_func` detours (`nmr:librecomp/src/mods.cpp:558-593`), and the second is not solved by the JIT ritual at all. (b)/(c) would gate the whole port's UX on a fragile ritual to enable a feature that still half-breaks. Enforcement: an iOS compile-time definition (`BANJO_IOS_NO_CODE_MODS`) that makes `load_mod_code` refuse code mods with a clear error and hides the enable toggle for mods carrying `mod_syms.bin` in the mod menu. This also sidesteps the `ShimFunction` null-deref hardening gap (`n64recomp:LiveRecomp/live_generator.cpp:1969`).

**D2 — Renderer strategy: complete plume-Metal for iOS; no Vulkan/MoltenVK.**
Options: (a) plume-Metal + iOS gap-fill; (b) MoltenVK via plume-Vulkan (reuse Android's Vulkan fixes); (c) new backend.
Chosen: (a).
Why: macOS ships plume-Metal in production ("Automatic" → Metal on Apple, `rt64:src/common/rt64_user_configuration.cpp:142-152`), the iOS capability table already exists (`plume:plume_metal.cpp:3833-3837`), and the gap list is three API guards + one AppKit file + CMake (feasibility §5). MoltenVK adds a translation layer, a new dependency, and none of the Android Vulkan surface-lifecycle code applies to iOS's windowing anyway. (c) is absurd given (a).

**D3 — Where iOS code lives: banjopad owns everything; upstreams are pinned read-only inputs.**
Options: (a) fork each upstream repo on GitHub; (b) banjopad holds pinned checkouts + an ordered patch series applied by script; (c) submodules pointing at personal forks.
Chosen: (b), mirroring HarkinianPad (`harkinianpad:docs/ios-feasibility-and-implementation-plan.md` §G repository rule).
Why: upstream moves daily (feasibility R2); a patch series over exact pins is rebasable on our schedule, keeps a single publication surface, guarantees we never accidentally push, and makes every iOS change reviewable as a diff. Patches are grouped per target tree (`patches/banjo/`, `patches/nmr/`, `patches/rt64/` — plume patches live in the rt64 series since plume is vendored inside it, `patches/frontend/`), numbered, and applied by `scripts/fetch-sources.sh` after clone. Push URLs of fetched sources are set to `DISABLED` just as HarkinianPad does.

**D4 — App shell and entry: SDL2's native iOS backend; no custom UIKit app lifecycle.**
Options: (a) SDL2-iOS (UIKit under the hood) with `SDL_main`; (b) hand-rolled UIKit app hosting a CAMetalLayer and bypassing SDL video.
Chosen: (a).
Why: BanjoRecomp's window, events, audio, and input are all SDL (`banjo:src/main/main.cpp:86,160-198,696`); the Android port kept SDL ownership and it held up. SDL2-iOS provides the UIKit application object, the Metal view (`SDL_uikitmetalview`), touch events, AVAudioSession audio, and GameController-backed SDL_GameController. The desktop `SDL_MAIN_HANDLED` define must NOT be set on iOS; instead a small `ios_main.mm` provides `SDL_main` (calling the extracted platform-independent startup) and links `SDL2main`. The Android fork already extracted startup from desktop `main` (its plan Task 3) — we reuse that split (D14).

**D5 — Window handle meaning on iOS: `{UIWindow*, CAMetalLayer*}` through the existing `{window, view}` struct.**
Options: (a) reuse the Apple `RenderWindow {void* window; void* view;}` with iOS meanings; (b) new iOS-specific handle type.
Chosen: (a).
Why: the struct is `void*`-typed (`plume:plume_render_interface_types.h:53-62`) and only plume's Apple helper interprets it. On iOS, `window` = `UIWindow*` (from `SDL_GetWindowWMInfo` → `info.uikit.window`) and `view` = `CAMetalLayer*` (from `SDL_Metal_CreateView`/`SDL_Metal_GetLayer`, same calls as macOS, `banjo:src/main/main.cpp:192-194`). plume gets a `UIKitWindow` twin of `CocoaWindow` (D6). `ultramodern`'s mirrored handle (`nmr:ultramodern/include/ultramodern/renderer_context.hpp:59-65`) is `void*`-based on Apple and needs no change.

**D6 — plume window helper: a `UIKitWindow` twin of `CocoaWindow` in a new `plume_uikit.mm`.**
Sizes from `CAMetalLayer.bounds × contentsScale` (authoritative on iOS) with the `UIWindow`'s `windowScene.screen` supplying `maximumFramesPerSecond`; `toggleFullscreen()` is a no-op; the IOKit vendor path is compiled out (every iOS GPU short-circuits to `RenderDeviceVendor::APPLE` via the `GPUFamilyApple1` check at `plume:plume_metal.cpp:3801` anyway). File selection in plume's CMake: `plume_apple.mm` for `PLUME_MACOS`, `plume_uikit.mm` for `PLUME_IOS`.

**D7 — Shader pipeline: keep the offline HLSL→SPIR-V→MSL→metallib chain; retarget the two `xcrun` lines; host-tools split for cross-compilation.**
Options: (a) retarget existing chain to `iphoneos`; (b) runtime MSL source compilation on device; (c) precompiled multi-target metallibs checked in.
Chosen: (a).
Why: the chain is already offline and embedded; only `rt64:CMakeLists.txt:146` and `:149` name the SDK. (b) adds startup cost and abandons function-constant specialization for nothing; (c) commits generated binaries to the repo. Host tools (DXC prebuilt binaries, `spirv_cross_msl`, `file_to_c`, N64Recomp, RSPRecomp) run on the macOS build host; the iOS CMake configure receives their paths via cache variables — the same split the Android fork made for DXC (`android:lib/rt64/CMakeLists.txt:57-65`). Simulator builds add an `iphonesimulator` SDK variant of the two lines, keyed off `CMAKE_OSX_SYSROOT`.

**D8 — Frontend approach: recompui/RmlUi unchanged; NFD replaced behind the existing dialog seam; menus driven by SDL touch→mouse.**
Why: recompui renders through plume with MSL blobs already built under `__APPLE__` (`frontend:recompui/src/renderer/ui_renderer.cpp:19-33`), so it comes along with the renderer for free. The single desktop-only dependency is NFD (`frontend:recompui/src/util/file.cpp:24-56`); the Android fork established the pattern: null-NFD backend + platform picker + async completion callback (`complete_android_file_dialog`). iOS implements `open_file_dialog` with `UIDocumentPickerViewController` and a `complete_ios_file_dialog` mirror (D12). Menu interaction: SDL's touch→mouse synthesis, plus the existing controller navigation.

**D9 — Asset flow: user-supplied retail ROM at first launch via document picker; config root in `Documents/` (Files-visible); program assets from the app bundle.**
Options for config root: (a) `Application Support` (hidden); (b) `Documents` with `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` (visible in the Files app).
Chosen: (b).
Why: everything the user might want to touch — saves, mods folder for `.rtz` drops, the imported ROM — lives under librecomp's single `config_path` root (`banjo:src/main/main.cpp:713`); making that root Files-visible gives save export/backup and texture-pack installation *for free* (drop an `.rtz` into `Documents/mods/` from the Files app; rescan on foreground). HarkinianPad shipped exactly this posture. Program assets (`assets/`, `recompcontrollerdb.txt`) ship read-only in the app bundle and are resolved via a `get_program_path()` override to `[NSBundle mainBundle].resourcePath` (the seam the Android port used env vars for, `frontend:recompui/src/util/file.cpp:161-166` in its fork).

**D10 — Touch input injection: wrap the `get_input` callback; do not post SDL events; no SDL virtual controller in v1.**
Options: (a) wrap `ultramodern::input::callbacks_t::get_input`/`poll_input` (registered at `banjo:src/main/main.cpp:773-778`); (b) `SDL_JoystickAttachVirtual`; (c) post SDL key events.
Chosen: (a), with the camera stick routed through a parallel wrap of the right-analog source (see §5).
Why: gameplay input is *polled* state — posted key events never reach it (`frontend:recompinput/src/input_state.cpp:221-256`), ruling out (c) for gameplay. (b) works but detours through SDL's mapping layer, profiles, and the controller-detection UI for no benefit and with hotplug-UX side effects (a "controller" appearing in menus). (a) is a two-function shim, thread-correct (called on the same thread ultramodern already calls), and leaves recompinput untouched.

**D11 — Lifecycle: port the Android pause architecture to SDL-iOS application events.**
SDL delivers `SDL_APP_WILLENTERBACKGROUND`/`SDL_APP_DIDENTERBACKGROUND`/`SDL_APP_WILLENTERFOREGROUND`/`SDL_APP_DIDENTERFOREGROUND`/`SDL_APP_TERMINATING` on iOS (via an event filter, delivered synchronously — the handler must be registered early). On background: set the ultramodern app-paused flag (VI-thread gate — the Android fork's mechanism), pause+clear SDL audio, mark the plume swapchain unavailable so no `nextDrawable`/commit happens while backgrounded (Metal work in background = watchdog kill), and flush pending config/save writes synchronously. On foreground: reverse. The save writer is already atomic and event-driven (`nmr:librecomp/src/pi.cpp:138-163`, `files.cpp:3-45`); backgrounding adds one explicit flush.

**D12 — ROM/mod import UX: `UIDocumentPickerViewController` as the primary flow; Files-app drop as the implicit secondary.**
The picker feeds the *unchanged* validation flow: copy picked file (security-scoped) to `tmp/`, call `recomp::select_rom(path, game_id)` — byte-order normalization and XXH3 hash check included (`nmr:librecomp/src/recomp.cpp:305-411`) — then delete the temp. Mods: picked files are turned into synthesized `SDL_DROPFILE` events exactly as Android does (`android:src/main/main.cpp:190-212`), reusing the desktop installer path.

**D13 — Cherry-picks from the Android fork's N64ModernRuntime (platform-neutral fixes):**
(1) the OSTimer `std::set` fix (`android:lib/N64ModernRuntime/ultramodern/src/timer.cpp:100-168`) — upstream still has the freeze bug (`nmr:ultramodern/src/timer.cpp:88-137`); (2) the save quiesce/snapshot API (`snapshot_save_file`/`import_save_file`, `android:lib/N64ModernRuntime/librecomp/src/pi.cpp:355-400`) — not strictly needed for v1 but taken with (1) to keep the two forks' runtime patches aligned and to ready iCloud/Files save sync later. Both go into `patches/nmr/`.

**D14 — Startup split: adopt the Android fork's `banjo_recomp_main` extraction as a patch.**
The Android repo already split platform-independent startup from desktop `main` (its plan Task 3, present in `android:src/main/main.cpp`). We port that split (not the whole Android main.cpp) into `patches/banjo/`, then add the iOS entry (`ios/ios_main.mm`: `SDL_main` → platform setup → `banjo_recomp_main`).

**D15 — Targets and floor: iOS 16.0 minimum; arm64 device + arm64 simulator; landscape-only; iPad primary.**
Why 16.0: `bufferDeviceAddress` gating (`plume:plume_metal.cpp:3836`), a current-but-not-bleeding floor, and one less matrix dimension. Devices: officially A13+ (comfortable margin over the Apple3 code floor), best-effort back to Apple3. `UIRequiresFullScreen = YES` in v1 (opt out of iPad multitasking/resizing until a dedicated pass — RT64 handles desktop resizes but Stage Manager is untested; deferred decision DD3).

**D16 — Renderer defaults on iOS (first boot):** InternalColorFormat forced to Standard (defeat the `>512 MiB → HDR` auto at `plume:plume_metal.cpp:3826` / `rt64:src/hle/rt64_application.cpp:282-295`), MSAA off, resolution scale 1.0, framerate cap "Display". Revisit after Phase 8 measurements.

**Deferred decisions:**

- **DD1 — Touch-layout editor/haptics/custom art:** out of v1 (matches HarkinianPad's exclusion list). Settled by user feedback after release.
- **DD2 — Bundled offline mods** (OfflineModRecomp → static/embedded-framework + shim replacement + table-based redirection): out of scope until upstream exposes lookup-based replacement for base functions (feasibility Q7). Settled by upstream movement.
- **DD3 — iPad multitasking/Stage Manager support:** retain `UIRequiresFullScreen=YES` for the current landscape-only app. The 2026-07-29 resize-matrix pass on an iPad Pro 11-inch (M4), iPadOS 18.5 Simulator proved that removing the key while keeping landscape-only metadata does not meet Apple's adaptive-orientation contract, while declaring all orientations exposes true Stage Manager resizing but makes the landscape launcher and gameplay viewport unusable in portrait. A diagnostic plume refresh correctly changed the Metal drawable from `2420×1668` to `1668×2420`, but the launcher remained clipped and its menu moved offscreen; the experiment was reverted rather than shipping partial support. Reopen only with a dedicated landscape-canvas/letterboxing design, portrait-safe touch layout, and scene-size/orientation policy. Apple's migration guidance: [TN3192](https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key).
- **DD4 — iCloud save sync / save export UI:** deferred; Files-visible `Documents/saves/` plus D13's snapshot API is the v1 answer. Settled by demand.
- **DD5 — MTLBinaryArchive PSO caching:** deferred until Phase 8 measurement shows objectionable cold-start hitching (the async cache + ubershader fallback already smooths this, `rt64:src/render/rt64_raster_shader_cache.cpp:33-105`).
- **DD6 — Upstreaming:** after the port works, offer plume-iOS + timer fix upstream; until then everything stays in the patch series (D3).

---

## 3. Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│ banjopad/ios — app shell (new code, ~all of it Obj-C++/C++)         │
│   ios_main.mm            SDL_main → banjo_recomp_main               │
│   IosPaths.mm            Documents/bundle path providers            │
│   IosFileDialog.mm       UIDocumentPicker → complete_ios_file_dialog │
│   IosLifecycle.mm        SDL_APP_* handler → pause gates + flush    │
│   TouchOverlay.mm        UIView overlay → TouchState (lock-free)    │
│   TouchInputShim.cpp     wraps get_input / right-analog source      │
│   Info.plist.in, LaunchScreen.storyboard, icons, entitlements       │
├─────────────────────────────────────────────────────────────────────┤
│ banjo (pinned c20314c + patches/banjo)                              │
│   src/main/main.cpp      split: banjo_recomp_main (D14); iOS guards │
│   RecompiledFuncs/ RecompiledPatches/ rsp/   ← host-generated (AOT) │
├─────────────────────────────────────────────────────────────────────┤
│ frontend (pinned d0d90ba + patches/frontend)                        │
│   recompui   RmlUi 6.0 → renders through plume (MSL blobs exist)    │
│   recompinput SDL2 pads/keyboard (unchanged); touch lives ABOVE it  │
│   util/file.cpp   iOS branches: app folder→Documents, program→bundle │
│                   open_file_dialog→picker bridge; null NFD          │
├─────────────────────────────────────────────────────────────────────┤
│ nmr (pinned ca568b6 + patches/nmr)                                  │
│   librecomp  ROM/save/config/mods (code mods hard-off on iOS, D1)   │
│   ultramodern threads/timers(+D13 fix)/VI pause gate/audio/input cbs │
├─────────────────────────────────────────────────────────────────────┤
│ rt64 (pinned 6f1c2d9 + patches/rt64, includes plume)                │
│   plume_metal.cpp  + PLUME_IOS guards (3 sites)                     │
│   plume_uikit.mm   NEW UIKitWindow twin of CocoaWindow (D6)         │
│   CMake: iOS arm, -sdk iphoneos shader lines, host-tool overrides   │
├─────────────────────────────────────────────────────────────────────┤
│ SDL2 2.32.x static (iOS build)  │ FreeType static │ metal-cpp (in   │
│ UIKit window/touch/lifecycle, AVAudioSession audio, GameController  │ plume) │
└─────────────────────────────────────────────────────────────────────┘
```

Control flow at runtime is unchanged from desktop: `SDL_main` → `banjo_recomp_main` → registrations (`banjo:src/main/main.cpp:688-805`) → `recomp::start` (`nmr:librecomp/src/recomp.cpp:795`) — which creates the SDL window on the main thread via the `create_window` callback, spawns the game-start thread, and runs the main-thread `update_gfx` event pump (`recomp.cpp:875-893`). The launcher parks in `wait_for_game_started`; "Start Game" boots the recompiled entrypoint. UIKit's main-thread requirement is satisfied because SDL_main runs on the process main thread and all window/event work stays there; RT64 renders from ultramodern's gfx thread against the CAMetalLayer, which Metal permits.

Repository layout (banjopad):

```
banjopad/
  docs/                      this plan + feasibility + BUILDING-IOS.md (Phase 9)
  ios/                       app shell sources + plist/assets (new code, see diagram)
  patches/
    banjo/    NNN-*.patch    app-layer patches (main split, iOS guards, code-mod gate)
    nmr/      NNN-*.patch    timer fix, save API cherry-picks, VI pause gate, iOS bits
    rt64/     NNN-*.patch    plume iOS + CMake + shader retarget (plume is vendored here)
    frontend/ NNN-*.patch    file.cpp iOS branches, picker bridge, renderer stub gate
  scripts/
    fetch-sources.sh         clone pins into sources/, disable push URLs, apply patches
    build-host-tools.sh      N64Recomp, RSPRecomp, file_to_c, spirv_cross_msl (host)
    prepare-generated.sh     run recompilers against the local ROM → RecompiledFuncs/…
    build-ios.sh             configure+build the Xcode project (device/simulator)
    package-audit.sh         prohibited-content scan + IPA wrap (HarkinianPad pattern)
  sources/                   gitignored pinned checkouts
  build-host/ build-ios*/    gitignored build trees
```

Rule enforced by `.gitignore` + `package-audit.sh`: no ROM, no `RecompiledFuncs/`, `RecompiledPatches/`, `rsp/n_aspMain.cpp`, no `.z64/.v64/.n64`, and no generated artifacts are ever committed or packaged into a distributed archive.

---

## 4. Phased plan

Phases are ordered; each lists goal (observable outcome), file-level changes, commands, acceptance criteria, and verification. Do not start a phase before the previous one's acceptance is green (Track exceptions noted). Commands assume repo root `~/GitHub/banjopad` on an Apple-silicon Mac with Xcode 16+, CMake ≥3.24, Ninja, and a legally owned BK NTSC-U 1.0 ROM available locally (never committed).

### Phase 0 — Pinned sources, host tools, macOS baseline

**Goal (observable):** the pinned stack builds and runs as a *desktop macOS* app from `sources/`, proving pins + host toolchain + generated sources before any iOS work.

Changes:
- `scripts/fetch-sources.sh`: clone `BanjoRecomp/BanjoRecomp` at `c20314c` into `sources/banjo` with `--recurse-submodules`; verify every submodule SHA against the feasibility table; `git remote set-url --push origin DISABLED` in every checkout; apply `patches/*` (empty at this phase).
- `scripts/build-host-tools.sh`: build `N64RecompCLI` + `RSPRecomp` from `sources/banjo/lib/N64ModernRuntime/N64Recomp` (host arch), plus host builds of `file_to_c` and `spirv_cross_msl` (targets exist in the rt64/N64ModernRuntime trees; build them from a small host CMake superbuild). Outputs into `build-host/bin/`.
- `scripts/prepare-generated.sh <path-to-rom>`: verify sha1 `1fb13cad402518d3ae9a8dc4b52c5c54b2a4adc7` for the decompressed ROM (or produce it from a retail dump using `sources/banjo/lib/bk-decomp/tools/bk_rom_compressor`, accepting the byte-order normalization the Android notes describe); place as `sources/banjo/banjo.us.v10.decompressed.z64` (gitignored); run `./N64Recomp banjo.us.rev0.toml` and `./RSPRecomp n_aspMain.us.rev0.toml` from `sources/banjo` (matches `banjo:.github/workflows/validate.yml:82-88`). Idempotent, like Android's `prepare_android_generated_sources.sh`.
- macOS baseline: `cmake -S sources/banjo -B build-macos -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build-macos --target BanjoRecompiled`.

Acceptance: macOS `BanjoRecompiled` launches, imports a retail ROM, reaches the BK title screen with audio. `git status` in banjopad shows no generated/ROM files as untracked-and-committable (`.gitignore` proven).
Verification: run the game 5 minutes; confirm `~/Library/Application Support/BanjoRecompiled/` is created with config JSONs and `saves/bk.n64.us.1.0.bin` after an in-game save.

### Phase 1 — plume + RT64 compile for the iOS SDK  *(Track B start; the approach-proving phase)*

**Goal (observable):** `libRT64.a` (with plume inside it) and the embedded shader blobs build for `arm64-iphoneos` from a `CMAKE_SYSTEM_NAME=iOS` configure. Nothing user-facing — this is deliberately the smallest end-to-end proof that the renderer stack can exist on iOS.

Changes (all in `patches/rt64/`):
1. **plume CMake** (`sources/banjo/lib/rt64/src/contrib/plume/CMakeLists.txt`): make the macOS deployment-target block (`:5-8`) conditional on `NOT CMAKE_SYSTEM_NAME STREQUAL "iOS"`; source selection — `plume_apple.mm` only for macOS, new `plume_uikit.mm` for iOS; keep metal-cpp include path arm.
2. **`plume_uikit.mm` (new)**: `UIKitWindow` implementing the `CocoaWindow` interface surface consumed at `plume:plume_metal.cpp:1919, 2096-2107` — attributes `{x=0, y=0, width, height}` from `CAMetalLayer.bounds × contentsScale`, refresh rate from `UIWindow.windowScene.screen.maximumFramesPerSecond` (fallback 60), `toggleFullscreen()` no-op. Guard the class choice in `plume_metal.cpp:1919` on `PLUME_IOS` (or make the helper name common via a typedef in `plume_apple.h`).
3. **Three `PLUME_IOS` guards in `plume_metal.cpp`**: `MTL::CopyAllDevices()` → `CreateSystemDefaultDevice`-only on iOS (`:3782`, `:4196`; fallback already at `:3793`); `mtl->location()` device-type mapping → report `INTEGRATED` on iOS (`:3799`); `setDisplaySyncEnabled`/`displaySyncEnabled` → no-op/true on iOS (`:2025`, `:2030`).
4. **rt64 CMake** (`sources/banjo/lib/rt64/CMakeLists.txt`): iOS arm — skip IOKit in the framework list (`:460` → Metal/QuartzCore/CoreGraphics/UIKit for iOS); shader chain: replace the two hardcoded lines `:146` (`xcrun -sdk macosx metal`) and `:149` (`metallib`) with an `RT64_APPLE_METAL_SDK` variable — `macosx` default, `iphoneos`/`iphonesimulator` when `CMAKE_SYSTEM_NAME=iOS` (keyed off `CMAKE_OSX_SYSROOT`), adding `-mios-version-min=16.0`; take `DXC`, `SPIRV_CROSS_MSL`, `FILE_TO_C` from cache variables when cross-compiling (Android's pattern, `android:lib/rt64/CMakeLists.txt:57-65`) pointing into `build-host/bin`; audit `rt64_apple.mm` (`:456-458`) for AppKit use and guard as needed.
5. A thin `ios/cmake/rt64-only.cmake` harness project that builds just `rt64` (so Phase 1 doesn't need the whole app to configure).

Commands:
```
cmake -S ios/cmake -B build-ios-rt64 -G Xcode -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DDXC_PATH=... -DSPIRV_CROSS_MSL_PATH=$PWD/build-host/bin/spirv_cross_msl \
  -DFILE_TO_C_PATH=$PWD/build-host/bin/file_to_c
cmake --build build-ios-rt64 --config Release --target rt64
```

Acceptance: `rt64` target links for arm64-iphoneos with zero AppKit/IOKit symbols (`nm -um … | grep -c "NSWindow\|IOService"` = 0); every `*BlobMSL` C array is generated through the `iphoneos` metallib; the same configure with `-DCMAKE_OSX_SYSROOT=iphonesimulator` also builds.
Verification: `otool -l libRT64.a` objects show `LC_BUILD_VERSION platform IOS minos 16.0`; a `metallib` from the build tree passes `xcrun metal-readlib` (or loads in a scratch iOS app).

### Phase 2 — Metal smoke harness on device *(Track B)*

**Goal (observable):** a minimal iOS app (SDL window + plume swapchain) clears the screen to a solid color and presents at 60 Hz on a physical iPad, surviving background/foreground.

Changes:
- Build **SDL2 2.32.10 static for iOS** (CMake, `-DCMAKE_SYSTEM_NAME=iOS`; pin the same release the Android port uses) — add to `scripts/build-ios.sh` as a dependency step; and **FreeType static for iOS** (needed in Phase 3; build both now).
- `ios/smoke/` harness: `SDL_Init(VIDEO)`, `SDL_CreateWindow(... SDL_WINDOW_METAL | SDL_WINDOW_FULLSCREEN)`, `SDL_Metal_CreateView`/`SDL_Metal_GetLayer`, `SDL_GetWindowWMInfo` → `info.uikit.window`, build a plume `RenderInterface`(Metal) + device + swapchain from `{UIWindow*, CAMetalLayer*}`, loop: acquire → clear via plume's clear path → present; handle `SDL_APP_*` events by stopping acquisition while backgrounded.
- Xcode signing with the personal/dev team via CMake `XCODE_ATTRIBUTE_DEVELOPMENT_TEAM`.

Acceptance: solid-color present on device; rotation stays landscape; 20 background/foreground cycles with no crash and no GPU-watchdog kill; simulator run best-effort.
Verification: Metal System Trace (Instruments) shows steady present cadence; `nextDrawable` never called while backgrounded (add an assert in the harness).

This phase exists because the Android bring-up found silent black-screen classes of bugs (surface formats, descriptor layouts) *below* the game; catching plume-Metal-on-iOS issues here is 10× cheaper than inside the full app. Any fix lands in `patches/rt64/`.

### Phase 3 — Full app cross-compiles; boots headless with renderer stub *(Track A)*

**Goal (observable):** the complete `BanjoRecompiled` app (game code included) installs and launches on device with the renderer stubbed; logs prove launcher init, config creation in `Documents/`, audio device open, and controller enumeration. Runs in parallel with Phase 2 after Phase 1.

Changes:
- `patches/banjo/`: adopt the `banjo_recomp_main` split (D14); guard desktop-only pieces for `TARGET_OS_IPHONE` (console/icon code is already `_WIN32`/`__gnu_linux__`-gated — audit `banjo:src/main/main.cpp:660-689`); NFD init/quit behind `#if !TARGET_OS_IPHONE` (`:689`); `preload_executable` treats iOS as no-op-success; **iOS CMake arm** in `sources/banjo/CMakeLists.txt`: no ld64 wrapper (`:206-213` macOS-only — verify it is inside an `elseif(APPLE)` that must now exclude iOS), static SDL2/FreeType paths, `MACOSX_BUNDLE` target props, Info.plist template from `ios/`, treat `RecompiledPatches/` + `rsp/n_aspMain.cpp` as prepared inputs when cross-compiling (do NOT register the patch-regen custom commands that run host clang/make — Android's clean-build lesson), `BANJO_IOS_NO_CODE_MODS` definition (D1).
- `patches/frontend/`: port the Android fork's null-NFD + `NullRendererContext` + stub gate (rename to `BANJO_MOBILE_RENDERER_STUB`); `util/file.cpp` iOS branches — `get_app_folder_path()` → `NSDocumentDirectory`, `get_program_path()` → `[NSBundle mainBundle].resourcePath` (keep the macOS branches intact).
- `patches/nmr/`: D13 cherry-picks (timer fix + save quiesce API); code-mod gate: in `load_mod_code`, `#ifdef BANJO_IOS_NO_CODE_MODS` return `FailedToLoadCode` with a distinct message before any `LiveRecompilerCodeHandle`/`DynamicLibraryCodeHandle` construction (`nmr:librecomp/src/mods.cpp:2370-2410`), and suppress the enable toggle in the mod menu for mods whose content types include the code type.
- `ios/ios_main.mm`, `ios/IosPaths.mm`, `ios/Info.plist.in` (keys in §7), `LaunchScreen.storyboard`, icon set.
- RT64's data path: patch `rt64:src/common/rt64_user_paths.cpp` to use Application Support on iOS (the `$HOME` fallback class of bug that bit Android with `/data/.rt64`).

Commands: `scripts/build-ios.sh --stub --config Debug` → `cmake -S sources/banjo -B build-ios -G Xcode -DCMAKE_SYSTEM_NAME=iOS …` → `xcodebuild -project … -destination 'generic/platform=iOS'` → install via `xcrun devicectl device install app`.
Acceptance: app launches on device; log shows launcher init sequence, `Documents/` gains config JSONs on first run; `SDL_GetNumAudioDevices` > 0 and the audio device opens at 48 kHz (`reset_audio`, `banjo:src/main/main.cpp:697`); a paired MFi/BT controller enumerates in the log; process survives 10 minutes idle + 10 bg/fg cycles. Screen may be black — that is expected under the stub.
Verification: pull the container (`devicectl` or Xcode → Devices) and diff config JSONs against a desktop first-run; confirm **no** code-mod path is reachable by placing a code-mod `.nrm` in `Documents/mods` and observing the gated error, not a crash.

### Phase 4 — Real renderer: launcher renders; menus usable *(tracks merge)*

**Goal (observable):** with the stub off, the BanjoRecomp launcher (RmlUi through RT64/plume-Metal) renders correctly on device; touch taps navigate every menu.

Changes: turn off the stub in the build script; fix what breaks (this is the bug-burn-down phase — expected: swapchain sizing from the layer, contentsScale vs SDL logical size, UI scale). Wire `SDL_HINT_TOUCH_MOUSE_EVENTS=1` early in `ios_main.mm`. UI scale: reuse the existing 1080p-referenced density scale (`frontend:recompui/src/base/ui_state.cpp:873`) — validate on iPad 11"/13" and iPhone; if unreadable on iPhone, apply a compact-scale factor keyed on shortest-side points (HarkinianPad's rule).
Acceptance: launcher shows the animated BK menu (`Load ROM`, `Controls`, `Settings`, `Mods`, `Exit`); all tabs open and are readable on iPad and iPhone; no validation-layer errors with Metal API validation on; 30 minutes of menu idling with no leak growth (Instruments).
Verification: screenshot set (iPad landscape, iPhone landscape); Metal frame capture of one launcher frame showing the RmlUi draw pass in RT64's swapchain framebuffer.

### Phase 5 — ROM import; game boots to title; audio

**Goal (observable):** a user with only the app and a retail ROM on the device reaches the BK title screen with sound, no desktop involved.

Changes:
- `ios/IosFileDialog.mm` + `patches/frontend/`: implement `recompui::file::open_file_dialog` on iOS via `UIDocumentPickerViewController` (UTType list: `public.data` + a declared `.z64/.v64/.n64` UTI set), presented from SDL's root view controller; async completion → `complete_ios_file_dialog(bool, path)` mirroring the Android seam; security-scoped copy to `tmp/rom-import/`.
- Mods path: same picker (multi-select) → synthesized `SDL_DROPFILE` events (port of `android:src/main/main.cpp:190-212`).
- Foreground rescan: on `SDL_APP_DIDENTERFOREGROUND`, rescan `Documents/mods` so Files-app `.rtz` drops appear without relaunch.
Acceptance: pick ROM in any of the three byte orders → validation passes (wrong ROM → the existing correct error strings); `Documents/bk.n64.us.1.0.z64` appears; Start Game reaches the title screen with music; an `.rtz` texture pack dropped via Files and enabled in the Mods menu visibly replaces textures in-game.
Verification: relaunch → "Start Game" directly (stored-ROM hash re-check passes, `nmr:librecomp/src/recomp.cpp:197-221`); audio underrun check — if crackling, tune `SDL_AudioSpec.samples` (desktop `0x100`; Android needed `0x800`; find the iOS floor empirically and gate it `TARGET_OS_IPHONE`-only).

### Phase 6 — Input: MFi controller + touch overlay v1

**Goal (observable):** the game is fully playable with (a) a Bluetooth/MFi controller and (b) the touch overlay per §5, including the Z-hold combo moves.

Changes: bundle `recompcontrollerdb.txt` in resources (already resolved via `get_program_path()`); `ios/TouchOverlay.mm`, `ios/TouchInputShim.cpp` (§5); a "Touch Controls" toggle row added to the Controls tab (persisted in `controls.json`-adjacent iOS config).
Acceptance: §5's acceptance checklist passes on iPad; controller: pair a PS/Xbox/MFi pad, full playthrough of Spiral Mountain including talon trot, eggs, wonderwing, camera; rumble works if the pad supports it.
Verification: simultaneous-touch stress (stick held + Z held + C tapped); overlay hidden while the config menu is open and restored after; toggle off releases all held inputs.

### Phase 7 — Lifecycle and save correctness

**Goal (observable):** backgrounding mid-game, force-kill, and relaunch lose nothing; no watchdog kills across a suspend matrix.

Changes: `ios/IosLifecycle.mm` per D11 — SDL event watch registered before `recomp::start`; ultramodern VI-pause flag (port Android's gate into `patches/nmr/` if not already via D13); plume-Metal "swapchain unavailable while backgrounded" guard in `patches/rt64/`; synchronous config write + save-thread flush on `WILLENTERBACKGROUND`; audio pause/clear + reopen on foreground.
Acceptance matrix (each ×5): background during gameplay → foreground (resumes, audio returns); background → force-kill → relaunch (save present, settings intact); phone call / Siri interruption during gameplay; lock/unlock; 30-minute suspend. Zero watchdog terminations (check crash logs on device).
Verification: after an in-game save then immediate background+kill, `saves/bk.n64.us.1.0.bin` hash matches a desktop save at the same point; `.bak` discipline intact (`nmr:librecomp/src/files.cpp:3-45`).

### Phase 8 — Performance and thermal pass

**Goal (observable):** measured, recorded baselines; the game holds its target framerate on the primary device class with acceptable thermals.

Work: measure on M-series iPad and the oldest committed device (A13): steady-state fps in Spiral Mountain + Mumbo's Mountain, cold-start PSO-compile hitch profile, memory footprint (expect ROM-in-memory ~32 MB + RDRAM allocation + renderer buffers — record actuals), 20-minute thermal soak. Tune D16 defaults; decide DD5 (MTLBinaryArchive) from the hitch data; verify Release uses `-O2`+ (Android's `-O0` lesson).
Acceptance: stable 60 (or the framerate-cap setting honored) on iPad primary; no jetsam kills; documented numbers in `docs/perf-baseline.md`.

### Phase 9 — Packaging, signing, docs, CI

**Goal (observable):** a tagged banjopad release from which a competent developer goes clone → device install using only the docs; CI proves the ROM-free invariant on every push.

Changes: `scripts/package-audit.sh` (HarkinianPad `package-ios.sh` pattern: scan the built .app for `.z64/.v64/.n64`, `RecompiledFuncs`, `banjo.us`, ROM hashes; `REQUIRE_SIGNED=1` enforces a valid signature + embedded profile before IPA wrap); `docs/BUILDING-IOS.md` (toolchain versions, ROM prep, signing with a personal team, simulator notes); GitHub Actions on `macos-15`: fetch pins → apply patches → build host tools → **stub-mode** iOS build (no ROM in CI; the full-game target stays local-only unless a private-inputs repo is configured — both modes scripted, mirroring `banjo:.github/workflows/validate.yml`'s secret-repo pattern and the Android probe/runtime split) → package-audit must pass.
Acceptance: green CI on a clean runner; an unsigned IPA artifact that installs via personal signing (AltStore/Sideloadly path documented, per `harkinianpad:docs/INSTALL_IPA.md` precedent); tag `v0.1.0`.

---

## 5. Touch control specification

Implementable as written; no further design needed. All coordinates in points, landscape, offsets measured from the **safe-area** edges (`view.safeAreaInsets` applied first). iPhone uses the same anchors with every size multiplied by 0.85. Rendering: UIKit layer (CAShapeLayer/UILabel) overlay view added above SDL's view; near-black fill at 33% opacity, 2 pt light border, white labels, brighter fill while pressed (HarkinianPad styling). No textures, no haptics, no editor in v1 (DD1).

### 5.1 Layout

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                             [•••]    │
│                                                                      │
│                                                                      │
│  [ Z ]                                                    [ R ]      │
│  [ L ]*                                              ( B )  ( A )    │
│    ( control stick )                    [Start]      (C-diamond)     │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
        * hidden by default                • camera-drag region = right half,
                                            excluding all controls
```

| Control | Shape/size (pt) | Position (safe-area offsets) | Emits |
|---|---|---|---|
| Control stick | circle, 150 base / 60 thumb | center at (left+120, bottom−120) | analog stick (§5.3) |
| Z (left) | pill 84×44 | center (left+96, bottom−232) — above stick, index/thumb reach | `Z` (N64 bitmask via shim) |
| L | pill 84×44 | center (left+96, bottom−288), **hidden by default** (BK uses L only for a replay dialogue-skip; mods may use it) — shown via Settings toggle | `L` |
| A | circle 66 | center (right−78, bottom−188) | `A` |
| B | circle 66 | center (right−156, bottom−210) — up-left of A | `B` |
| R | pill 84×44 | center (right−110, bottom−280) — above A/B | `R` |
| C-diamond (4× circle 46) | diamond footprint 150×150 | center (right−120, bottom−84); C-Up top, C-Down bottom, C-Left left, C-Right right | `C_UP/C_DOWN/C_LEFT/C_RIGHT` |
| Z (right) | circle 46 | center (right−232, bottom−120) — left of the C-diamond | `Z` (duplicate; same bit) |
| Start | pill 96×40, label "START" | center (right−320, bottom−40) | `START` |
| Menu `•••` | circle 38 | center (right−36, top+24) | opens/closes the config menu (calls the same path as `TOGGLE_MENU`) |
| D-pad | 4× circle 46, cross footprint 140×140 | center (left+120, bottom−320), **hidden by default** (BK ignores the D-pad; mods only) | `DPAD_*` |

Z is deliberately duplicated: left pill for stick-hand holds (talon trot = hold Z + C-Left), right small circle for face-hand holds (eggs = Z + C-Up/C-Down while aiming with the stick). Both emit the same bit; either sustains a hold.

### 5.2 Input injection (the shim)

- `ios/TouchInputShim.cpp` owns a `TouchState { std::atomic<uint16_t> buttons; std::atomic<float> stick_x, stick_y; std::atomic<float> cam_x, cam_y; }` written by the overlay on the UI thread, read lock-free from the input callbacks.
- Registration (in `banjo_recomp_main`, iOS only): replace `input_callbacks.get_input = recompinput::profiles::get_n64_input` (`banjo:src/main/main.cpp:773-778`) with a wrapper that calls the original, then `buttons |= touch.buttons`, `x = clamp(x + touch.stick_x)`, `y = clamp(y + touch.stick_y)`. Button bits use the same `n64_button_values` mapping recompinput uses (`frontend:recompinput/include/recompinput/input_types.h:10-24`).
- Camera: wrap the registered `recomp_get_right_analog_inputs` export (`banjo:src/main/main.cpp:727` → `banjo:src/game/recomp_api.cpp:213-225`) the same way: returned right-stick values OR in `touch.cam_x/cam_y`. On iOS first run, default the game's **Analog Camera** option ON (`banjo:src/game/config.cpp:41-62`) so drag-to-look works out of the box; C-Left/C-Right still rotate in the classic scheme if the user turns it off.
- Menu taps need nothing: SDL touch→mouse synthesis drives RmlUi (`SDL_HINT_TOUCH_MOUSE_EVENTS=1`); the overlay must `hitTest` transparent for touches that don't land on a control.

### 5.3 Control behaviors

- **Stick**: touch-down inside the base circle captures the touch id; thumb offset ÷ (75 − 30) maps to [−1, 1] per axis, radially clamped; values feed the shim continuously; touch-up recenters to (0,0). No dead zone in the overlay (ultramodern applies the N64 octagonal mapping downstream, `nmr:ultramodern/src/input.cpp:131-151`). A second touch inside the base while one is captured is ignored.
- **Buttons/pills** (A, B, Z×2, R, L, Start, C, D-pad): press on touch-down inside the hit circle (hit radius = visual radius + 6 pt), release on touch-up/cancel or when the touch slides > 20 pt outside the hit circle. Each control tracks its own touch id — simultaneous independent holds are required (acceptance: hold left-Z + tap C-Up fires an egg; hold Z + C-Left enters talon trot).
- **C-diamond**: each of the four circles is an independent button (no swipe-gesture semantics); diagonal simultaneous presses allowed.
- **Camera drag region**: any touch beginning on the right half of the screen that does not begin on a control and moves ≥ 8 pt becomes a camera drag; horizontal/vertical delta × sensitivity (default 1.0, exposed under the existing Analog Camera sensitivity setting) maps to `cam_x/cam_y` each frame, decaying to 0 on release. A touch that never exceeds 8 pt is delivered to SDL as a normal tap (menu/game).
- **Menu `•••`**: posts the same action as the bound `TOGGLE_MENU` input (open the recompui config modal). It is a separate always-installed control: it remains on screen even when gameplay touch controls are disabled, so the user can never be stranded.

### 5.4 Modes and state transitions

1. **Gameplay, touch enabled** (default on iOS first run): full overlay visible.
2. **Config menu open**: gameplay overlay hides and *releases every held input* (zero the TouchState); `•••` stays. On menu close, overlay returns only if the setting is still enabled. Hook: the same code path that opens/closes the recompui modal (`frontend:recompui/src/base/ui_state.cpp:811-843`).
3. **Setting off** (Settings → Controls → "Touch Controls"): overlay removed immediately, inputs released; persisted; `•••` remains.
4. **Controller connected**: overlay auto-fades to 40% opacity (still active); optional "Hide when controller connected" toggle (default off) removes it entirely. Hook: SDL controller add/remove events already pass through `frontend:recompinput/src/input_events.cpp:73-106`.
5. **Backgrounding**: TouchState zeroed on `WILLENTERBACKGROUND` (no stuck inputs on resume).

### 5.5 Acceptance checklist (Phase 6 gate)

1. Clean install shows stick + Z/L-row (L hidden) + A/B/R + C-diamond + right-Z + Start + `•••`, non-overlapping, lower-half only, on iPad 11" and 13" and iPhone 15-class.
2. Start advances the title screen; A/B navigate file select.
3. Spiral Mountain: move, jump (A), attack (B), talon trot (hold Z-left + C-Left), fire eggs (hold Z-right + C-Up), wonderwing (Z + C-Right), first-person (C-Up), camera drag pans when Analog Camera is on, R centers.
4. Menu open hides+releases; close restores; toggle works without restart; `•••` never disappears.
5. 10-finger mash produces no stuck inputs (release-all on cancel verified).
6. Controller pairing mid-session fades the overlay; unpairing restores it.

---

## 6. Asset and save pipeline specification

### 6.1 First launch, from the user's perspective

1. Install the app (sideload). Launch → BK-themed launcher appears (no ROM required to reach it; the game-start thread parks in `wait_for_game_started`, `nmr:librecomp/src/recomp.cpp:875-886`).
2. Primary button reads **Load ROM** (`frontend:recompui/src/base/ui_launcher.cpp:450-484`). Tap → iOS document picker (Files: any provider — On My iPad, iCloud, third-party).
3. User picks their retail dump (`.z64`, `.v64`, or `.n64` — all three byte orders accepted and normalized, `nmr:librecomp/src/recomp.cpp:305-344`).
4. Validation runs (XXH3-64 must equal `0x1B67585D56E07F8C`, `banjo:src/main/main.cpp:376`). Wrong version/game → the existing specific error dialogs (`ui_launcher.cpp:430-433`). Success → normalized copy written to `Documents/bk.n64.us.1.0.z64` (`recomp.cpp:408`); picker temp deleted; button flips to **Start Game**.
5. Tap Start Game → recompiled entrypoint runs; title screen. Total time: seconds (no extraction step exists in this stack — assets stream from the in-memory ROM, `nmr:librecomp/src/pi.cpp:14-85`).
6. Subsequent launches: stored ROM is re-hashed at startup (`recomp.cpp:197-221`; silently deleted+re-prompted if corrupted) and the launcher goes straight to Start Game.

Texture packs: user drops an `.rtz` into `Documents/mods/` via the Files app (folder pre-created at first run, `recomp.cpp:94`) **or** uses Mods → Install (picker, multi-select) which routes through synthesized `SDL_DROPFILE` events into the existing installer (`frontend:recompui/src/composites/ui_mod_installer.cpp:32-60`). Foreground rescan makes Files drops appear without relaunch (Phase 5). Code mods: shown with a "not supported on iOS" state (D1).

### 6.2 Code path behind it (all existing, seams only)

| Step | Code | iOS change |
|---|---|---|
| Config root | `recomp::register_config_path(recompui::file::get_app_folder_path())` — `banjo:src/main/main.cpp:713` | `get_app_folder_path()` → `NSDocumentDirectory` (`patches/frontend/`) |
| Program assets | `get_program_path()/assets`, `…/recompcontrollerdb.txt` (`banjo:src/main/main.cpp:703-710`) | `get_program_path()` → bundle `resourcePath` |
| Picker | `open_file_dialog` (`frontend:recompui/src/util/file.cpp:24-56`) | UIDocumentPicker impl + `complete_ios_file_dialog` |
| Validation/copy | `recomp::select_rom` (`nmr:librecomp/src/recomp.cpp:360-411`) | none |
| Boot load | `load_stored_rom` → in-memory ROM (`recomp.cpp:701-715`, `pi.cpp:14`) | none |
| RT64 data dir | `rt64:src/common/rt64_user_paths.cpp` | route to Application Support (Phase 3) |

### 6.3 Saves

- Format/location: raw 0x800-byte EEPROM image at `Documents/saves/bk.n64.us.1.0.bin` (`nmr:librecomp/src/pi.cpp:99-113,209-224`), written by the event-driven save thread with `.temp`/`.bak` atomic promotion (`pi.cpp:138-163`, `files.cpp:3-45`). Files-visible for user backup by construction (D9).
- Lifecycle guarantees (Phase 7): on background — flush the save thread (drain pending signals) and write config JSONs synchronously; on force-kill after background, the last completed atomic write is intact by design; `.bak` fallback covers a mid-write kill (`files.cpp:12-21`).
- Future (DD4): the D13-cherry-picked `snapshot_save_file`/`import_save_file` quiesce API is the hook for iCloud sync or an in-app export/import UI; not wired in v1.
- iTunes/Finder file sharing and the Files app both see `Documents/` (Info.plist keys below), so "copy save off the device" needs zero code.

---

## 7. Build, signing, and distribution

**Toolchain:** macOS 15+, Xcode 16+ (iOS 18 SDK; deployment target 16.0), CMake ≥ 3.24 (native `CMAKE_SYSTEM_NAME=iOS` support; no third-party toolchain file needed — HarkinianPad needed leetal/ios-cmake only because libultraship's CI predated modern CMake iOS support), Ninja for host builds, Python 3 for scripts.

**Configure (device):**
```
cmake -S sources/banjo -B build-ios -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DBANJO_IOS=ON -DBANJO_IOS_NO_CODE_MODS=ON \
  -DSDL2_IOS_PREFIX=$PWD/build-ios-deps/sdl2 -DFREETYPE_IOS_PREFIX=$PWD/build-ios-deps/freetype \
  -DDXC_PATH=… -DSPIRV_CROSS_MSL_PATH=… -DFILE_TO_C_PATH=… \
  -DXCODE_ATTRIBUTE_DEVELOPMENT_TEAM=<TEAMID> -DBUNDLE_ID=com.<yours>.banjopad
```
Simulator: same + `-DCMAKE_OSX_SYSROOT=iphonesimulator` (shader SDK follows, Phase 1). All of this is wrapped by `scripts/build-ios.sh`.

**Info.plist keys (ios/Info.plist.in):** `UIFileSharingEnabled=YES`; `LSSupportsOpeningDocumentsInPlace=YES`; `UISupportedInterfaceOrientations` = landscape-left/right only (both idioms); `UIRequiresFullScreen=YES` (D15); `UIStatusBarHidden=YES` + `UIViewControllerBasedStatusBarAppearance=NO`; `GCSupportsControllerUserInteraction=YES`; `GCSupportedGameControllers` = ExtendedGamepad; `UIApplicationSupportsIndirectInputEvents=YES`; `UILaunchStoryboardName=LaunchScreen`; `CFBundleDocumentTypes`/`UTExportedTypeDeclarations` for `.z64/.v64/.n64` and `.rtz`/`.nrm` (enables "Open in banjopad" share-sheet imports later); `MinimumOSVersion` 16.0.

**Entitlements:** none beyond the default app sandbox. Explicitly **no** `get-task-allow` in release builds, no JIT-related entitlements (D1), no iCloud (v1). The absence of special entitlements is the point — personal-team signing suffices.

**Device install paths:** (1) Xcode/`devicectl` for development; (2) `xcodebuild archive` + `-exportArchive` with a development/ad-hoc profile for personal IPAs; (3) **unsigned IPA release artifact** — built app zipped as `.ipa` by `package-audit.sh` after the prohibited-content scan — users sign with AltStore/Sideloadly/SideStore (documented in `docs/BUILDING-IOS.md` + an INSTALL doc mirroring `harkinianpad:docs/INSTALL_IPA.md`). TestFlight/App Store: explicitly out of scope (feasibility L3).

**ROM-free enforcement:** `.gitignore` covers `sources/`, `build*/`, `*.z64/*.v64/*.n64`, `RecompiledFuncs/`, `RecompiledPatches/`, `rsp/n_aspMain.cpp`; `package-audit.sh` fails the build if the .app contains ROM extensions, known ROM hashes, or generated-source markers *other than* the compiled binary itself; CI runs it on every push (Phase 9). The distributed binary necessarily embeds recompiled ROM-derived code — identical posture to every upstream BanjoRecomp release on every platform (feasibility L1); the IPA adds no new class of content.

---

## 8. Risks

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | plume-Metal first-frame bugs on iOS (untested path; Android hit the Vulkan analogs) | High | Schedule | Phase 2 smoke harness isolates them below the game; Metal API validation + frame capture in the loop; fixes are small patches in `patches/rt64/` |
| R2 | **Upstream moves daily** (BanjoRecomp; nmr/rt64/plume weekly) | Certain | Patch drift | Pins + patch series (D3). Rebase procedure: bump pins on a chosen cadence (e.g. after upstream releases), `fetch-sources.sh` re-applies patches, fix rejects, re-run Phase-gates 0/1/4/5 smoke checks. Never track upstream HEAD during a phase. If upstream lands overlapping work (e.g. plume iOS), drop our patch in favor of theirs at the next bump |
| R3 | OSTimer freeze (upstream bug) on iOS | Certain if unpatched | Game hangs | D13 cherry-pick from day one; watch upstream for a real fix |
| R4 | Watchdog kills from background GPU/audio work | High until Phase 7 | Rejection-level UX | Phase 7 is a gate before any distribution; explicit suspend matrix |
| R5 | Performance/thermal on A-series phones | Medium | Scope (device floor) | D16 conservative defaults; Phase 8 measurement; iPad-primary messaging; framerate cap options already exist |
| R6 | SDL2-iOS gaps for this stack (`SDL_GetWindowWMInfo` uikit info, Metal view semantics, audio buffer) | Medium | Days-scale delays | All have known shapes; Phase 2/3 surface them early; Android's audio-buffer lesson pre-planned |
| R7 | FreeType/dep cross-compile friction | Low | Days | Standard CMake iOS builds; static, pinned |
| R8 | PSO compile hitching worse on iOS than macOS | Medium | Polish | Ubershader fallback already covers correctness; DD5 (MTLBinaryArchive) if measurable |
| R9 | Simulator can't run the renderer (Metal feature gaps) | Medium | Dev convenience only | Device is the reference (Phase 1 acceptance keeps simulator best-effort) |
| R10 | Legal/takedown posture shift upstream (no LICENSE at banjo root; recompiled-code artifact) | Low | Distribution | Source-first + unsigned-IPA + audit script; never bundle ROM; track upstream posture; feasibility L1-L3 |
| R11 | A user-visible mod ecosystem expectation gap (code mods absent on iOS) | Medium | Community friction | Clear in-app messaging on gated mods; docs state the platform limitation and why (text-patching + JIT, not a choice) |

---

## 9. Rollback and recovery, per phase

Global property making rollback cheap: **every change is a numbered patch on pinned sources; no upstream state exists to unwind.** Reverting any phase = removing its patches + `fetch-sources.sh` re-run. Device-side: uninstalling the app removes the container (warn testers: export saves first via Files).

- **Phase 0:** nothing to roll back (scripts + gitignore). Recovery from a bad pin: re-pin to the feasibility table's SHAs (recorded in `scripts/fetch-sources.sh` as the single source of truth).
- **Phase 1:** patches are additive to rt64 CMake/plume; the macOS baseline build (Phase 0 acceptance) is the regression canary — it must stay green with the patches applied (the iOS arms are conditional). Roll back by dropping `patches/rt64/` numbers > last-good.
- **Phase 2:** harness is isolated in `ios/smoke/`; deleting it affects nothing else. If plume-Metal-on-iOS proves broken at a depth beyond the enumerated gaps (the R1 tail risk), the recovery decision point is here — reconsider D2 (MoltenVK fallback) with sunk cost limited to ~two phases.
- **Phase 3:** stub mode is a build flag; any regression in desktop behavior from the `banjo_recomp_main` split is caught by re-running the Phase 0 macOS build+play check (mandatory before closing Phase 3).
- **Phase 4:** renderer-stub flag remains permanently available as the fallback boot mode for triage; a broken renderer change reverts to stub to keep Track A testable.
- **Phase 5:** picker/import patches are frontend-isolated; the desktop NFD path is untouched (guards). Bad import states recover via the existing hash-recheck-and-delete on startup (`recomp.cpp:197-207`).
- **Phase 6:** overlay is fully behind the Touch Controls toggle + an `BANJO_IOS_TOUCH` compile flag; disable either to restore controller-only behavior. Shim wraps, never replaces, the original callbacks — removing the wrapper restores stock input.
- **Phase 7:** lifecycle handlers are additive; if a pause gate deadlocks, the flag flips it off (runtime-defaulted, compile-guarded) while keeping the synchronous save flush (the safe subset).
- **Phase 8:** settings-only changes; revert = restore D16 defaults.
- **Phase 9:** release artifacts are immutable tags; a bad release is superseded by the next tag; the audit script prevents the one unrecoverable mistake (shipping ROM content).
- **Pin-bump recovery (any time):** if a bump breaks more than a day's worth of rejects, abandon the bump (pins are per-repo — a partial bump of only e.g. `frontend` is legal), file the conflict list in `docs/`, retry next cadence.

---

## 10. Effort estimates

Every figure is an **estimate**, calibrated against the Android port's recorded bring-up (its notes span ~7 weeks of part-time work for a feature-complete port with JIT and Vulkan available) and HarkinianPad's iOS-side effort. Assumes one experienced C++/CMake developer with iOS familiarity, part-time; agent-assisted execution compresses wall-clock but not verification time.

| Phase | Estimate | Basis |
|---|---|---|
| 0 — Sources/host tools/baseline | 1-2 days | Scripting + one desktop build; all commands known |
| 1 — rt64+plume compile for iOS | 3-6 days | ~4 small patches + CMake surgery; unknowns are compile-time only |
| 2 — Metal smoke harness on device | 3-7 days | New harness + SDL2/FreeType iOS builds; the risk-burn phase (R1) |
| 3 — App cross-compile, stub boot | 4-8 days | Largest patch count (paths, guards, CMake arm, cherry-picks); Android's equivalent took similar effort with the plan in hand |
| 4 — Launcher renders, menus | 3-8 days | Bug-burn-down; Android's analog (black-screen → visible UI) consumed several sessions |
| 5 — ROM import, title screen, audio | 2-4 days | Picker + rescan + audio tune; validation flow unchanged |
| 6 — Controller + touch overlay | 5-8 days | Overlay geometry/state machine per §5 (new code, ~1-1.5k lines) + device iteration |
| 7 — Lifecycle + saves | 3-5 days | Pattern known from Android + HarkinianPad; matrix testing dominates |
| 8 — Perf/thermal | 2-4 days | Measurement + settings tuning; more if DD5 triggers (+2-3 days) |
| 9 — Packaging/CI/docs | 2-4 days | HarkinianPad templates exist for audit/IPA/docs |
| **Total** | **~28-56 working days** (≈ 6-11 part-time weeks) | Wide band dominated by R1 and Phase 4/6 iteration |

---

## 11. Open questions

Carried from feasibility (Q1-Q7 there) plus plan-level ones; each with what resolves it:

1. **Phase 2 outcome** — does plume-Metal present on iOS within the enumerated gap list, or is there a deeper incompatibility? Resolves R1 and validates D2; the plan's only "reconsider" gate (Phase 2 rollback note).
2. **`SDL_GetWindowWMInfo` on iOS** returns `info.uikit.window`; plume's helper needs the `UIWindow` only for screen/refresh queries — confirm the layer-only alternative (drop the window pointer entirely on iOS) during Phase 1/2; if clean, D5 simplifies to `{nullptr, CAMetalLayer*}`.
3. **Audio buffer floor on iOS** for this engine's queue-based feed (desktop 0x100 frames; Android needed 0x800). Resolved empirically in Phase 5.
4. **Simulator fidelity** for the full renderer (argument buffers + bindless on the simulator's Metal). Resolved in Phase 1/4; device remains the reference either way.
5. **iPhone UI scale** — is the existing 1080p-referenced RmlUi scale readable on 6-inch screens, or is a compact-mode factor needed (HarkinianPad needed one)? Resolved by Phase 4 acceptance on iPhone.
6. **Exact host-tool inventory** for cross-compilation — `file_to_c` and `spirv_cross_msl` build points are known; confirm no other in-tree tool is invoked during the iOS build graph (audit the generated build.ninja/Xcode project in Phase 1).
7. **Upstream reception** of plume-iOS/UIKitWindow and the timer fix (DD6). Resolved by proposing after Phase 4 proves the code.
8. **Whether upstream's mod system ever gains table-based replacement** (reopens code mods on iOS; DD2/feasibility Q7). Watch `N64Recomp/N64ModernRuntime`.
9. **Stage Manager/multitasking behavior** once `UIRequiresFullScreen` is lifted (DD3). Resolved 2026-07-29: retain full-screen until the landscape canvas, touch UI, and scene-orientation policy can survive arbitrary portrait and windowed sizes.
10. **Distribution channel beyond sideload** (AltStore PAL region availability for this kind of app; no App Store ambition). Resolved by policy review at release time; does not block v0.1.0.
