# BanjoRecomp on iOS/iPadOS — Feasibility Assessment

**Verdict: feasible and recommended.** No hard stop triggered. The load-bearing fear in the brief — that the base game requires runtime code generation — is wrong: the shipped game is fully ahead-of-time compiled, and every sljit/JIT path is reachable only through optional code mods. An install-and-play iOS build of the full game, with texture packs, is achievable without any JIT entitlement or pairing ritual. The renderer is the real work, and its gap list is short, enumerated, and localized.

Investigation date: 2026-07-28. Every claim about a repository below was verified against fresh clones at these revisions (`git submodule status --recursive`):

| Tree | Repo | Revision | Notes |
|---|---|---|---|
| `banjo` | BanjoRecomp/BanjoRecomp | `c20314c` (main, 2026-07-25 20:47 -0300) | the game/app layer |
| `nmr` | N64Recomp/N64ModernRuntime | `ca568b6` (branch `gamemodes`) | ultramodern + librecomp + nested N64Recomp |
| `n64recomp` | nested in `nmr` | `2b6f056` | recompiler + LiveRecomp + OfflineModRecomp |
| `sljit` | vendored in `n64recomp` | `f632608` | JIT backend of the live recompiler |
| `rt64` | rt64/rt64 | `6f1c2d9` (main) | renderer |
| `plume` | renderbag/plume (vendored `rt64:src/contrib/plume`) | `d890ac8` | rendering hardware interface |
| `frontend` | N64Recomp/RecompFrontend | `d0d90ba` (branch `include-order-fix`) | recompui (RmlUi 6.0) + recompinput |
| `bk-decomp` | gitlab.com/banjo.decomp/banjo-kazooie | `351ca15` | decomp headers/tools consumed by `patches/` |
| `syms` | BanjoRecomp/BanjoRecompSyms | `6820055` | symbol files |
| `android` | AurelioB/BanjoRecomp-Android | `2966e05` (2026-07-12) | the map; pins its own forks: nmr `3fc2e30` (main), rt64 `d0b87e6` (`audit/android-sdl-vulkan`), plume `2073b04`, frontend `497fbdd` |

Citations are `tree:path:lines`. Reference material: HarkinianPad (`/Users/chrissotraidis/GitHub/harkinianpad`), a completed iOS/iPadOS port of Ship of Harkinian by the same developer — its docs are the template for app-shell, signing, Files integration, and touch-control design. Note: the `ref/` folder in this repository is empty; the local harkinianpad checkout was used directly.

---

## 1. The JIT finding (Section A)

### 1.1 The one-line answer

**The base game performs zero runtime code generation.** `sljit` is linked unconditionally but only *invoked* by the mod system, and only when a code mod is loaded or a mod registers hooks. With no code mods enabled, no JIT memory is ever requested. A JIT-free build loses exactly one feature: runtime-loaded **code** mods. Texture packs, all base patches/enhancements, saves, and menus survive intact.

### 1.2 Trace of every path that reaches `live_recompiler_init()` and sljit

Boot path (runs every launch):

- `recomp::start()` calls `recomp::mods::initialize_mods()` unconditionally — `nmr:librecomp/src/recomp.cpp:836`.
- `initialize_mods()` calls `N64Recomp::live_recompiler_init()` — `nmr:librecomp/src/recomp.cpp:92-98` (the brief cited :86; actual :93).
- **`live_recompiler_init()` is harmless**: it sets five RabbitizerConfig pseudo-instruction flags and nothing else — no sljit call, no allocation — `n64recomp:LiveRecomp/live_generator.cpp:18-24`. Calling it at boot on iOS is a no-op risk-wise.

Actual sljit code-generation sites (exhaustive; all in `nmr:librecomp/src/mods.cpp` + `n64recomp:LiveRecomp/live_generator.cpp`):

1. **`LiveRecompilerCodeHandle` ctor** (`mods.cpp:479-524`) — constructs `N64Recomp::LiveGenerator` (`live_generator.cpp:73`, `sljit_create_compiler`) and emits code via `generator.finish()`. Created at:
   - `mods.cpp:2402` in `load_mod_code` — once per **code mod**. A mod is a code mod only if its container carries `mod_syms.bin` (content type registered `mods.cpp:900-907`; only such mods enter `loaded_code_mods` via `on_code_mod_enabled`, `mods.cpp:925-933`).
   - `mods.cpp:2048` inside `apply_regenlist`, called from `regenerate_with_hooks` at `mods.cpp:2085` (hooks into vanilla functions) and `mods.cpp:2133` (`base_patched_code_handle = apply_regenlist(patch_regenlist, overlays::get_patch_binary())` — the line the brief cited as :2117).
2. **`ShimFunction` ctor** (`live_generator.cpp:1955-1974`) — generates a tiny argument-injecting trampoline. Created in `resolve_code_dependencies` at `mods.cpp:2478` (code mod imports a base "ext export" API function) and `mods.cpp:2496` (unmet optional dependency stub). Runs for **every code mod, including offline/native ones**.

Gating, verified:

- `load_mods` (`mods.cpp:1574`) calls `regenerate_with_hooks` only `if (!unprocessed_hooks.empty())` (`mods.cpp:1802-1816`). `hook_slots` is populated exclusively while scanning **mod** hook definitions (`mods.cpp:2310-2313`). Zero mods → zero hooks → the regeneration machinery never runs.
- The base-patched regeneration at `mods.cpp:2133` runs only `if (!regenlist.patched_hooks.empty())` (`mods.cpp:2095`) — i.e. only when a loaded mod hooks a function that lives in the base patch set.
- BanjoRecomp registers **no embedded mods**. The only registration is `register_deprecated_mod("bk_recomp_mod_fov_slider", ...)` (`banjo:src/main/main.cpp:720`), a version-block marker with no content.

### 1.3 Does the base game run with live recompilation disabled? Yes — it never uses it

The brief's claim that "the base game's own patch set" runs through the live recompiler is **incorrect**. The base patch set is AOT-compiled at build time and statically linked:

- CI builds `N64RecompCLI` + `RSPRecomp` from source, then runs `./N64Recomp banjo.us.rev0.toml` and `./RSPRecomp n_aspMain.us.rev0.toml` (`banjo:.github/workflows/validate.yml:64-88`). This generates `RecompiledFuncs/*.c` (globbed at `banjo:CMakeLists.txt:81-84`; **not** committed — `git ls-files RecompiledFuncs` is empty).
- Patches: C sources in `banjo:patches/` → clang/ld.lld MIPS ELF (`banjo:CMakeLists.txt:120-124`) → `./N64Recomp patches.toml` → `RecompiledPatches/patches.c`, compiled into the static `PatchesLib` (`banjo:CMakeLists.txt:104-107`). A byte-array copy of `patches.bin` is also embedded (`file_to_c`, `banjo:CMakeLists.txt:126-130`) — that copy exists *solely* to feed `overlays::get_patch_binary()` for the mod-hook regeneration path.
- Boot with no mods: `wait_for_game_started` → `load_stored_rom` → `load_mods` (no code mods → no codegen) → `game_entry.entrypoint(rdram, context)` — a statically compiled function pointer (`nmr:librecomp/src/recomp.cpp:701-757`).

`OfflineModRecomp` is therefore **not needed for the base game at all** — the brief's "escape hatch" is how every build already works. `OfflineModRecomp` (`n64recomp:OfflineModRecomp/main.cpp:27-29`: `[mod symbol file] [mod binary file] [recomp symbols file] [output C file]`) matters only if you want *bundled mods* (see 1.6).

### 1.4 The second blocker the brief missed: runtime patching of the app's own text segment

Code mods do not just JIT — they **detour-patch the AOT binary**:

- `patch_func` (`mods.cpp:558-593`) memcpy's an absolute jump (ARM64: `ldr x2, #8; br x2` + 8-byte address, 16 bytes total, `mods.cpp:580-587`) over the target function's prologue **inside the app's own `__TEXT` segment**, via `mprotect(RW)` → `mprotect(RX)` (`mods.cpp:230-249`). Call sites: `mods.cpp:2063` (hook regenlist) and `mods.cpp:2637` (mod function replacement). `unpatch_func` restores bytes on unload (`mods.cpp:595-600`).
- macOS accommodates this with a **custom linker wrapper** — `banjo:.github/macos/ld64`, a Python script that rewrites the Mach-O `max_prot` of `__TEXT` to rwx — wired in at `banjo:CMakeLists.txt:206-213` ("required for mod function patching"). Windows uses `/OPT:NOICF` (`banjo:CMakeLists.txt:203-205`).
- On iOS this is a hard block for code mods **even with the JIT entitlement**: MAP_JIT legalizes anonymous RWX pages, not writes to codesigned executable pages; modified `__TEXT` pages fail signature revalidation outside fragile CS_DEBUGGED states.
- The base game is unaffected: with zero mods, `patch_func` is never called, and the iOS build simply omits the ld64 max_prot hack.

Consequence: **"JIT via StikDebug" does not cleanly deliver code mods on iOS.** It solves sljit's MAP_JIT allocation but not text detours. Both blockers land on the same feature (code mods) and neither touches the base game.

### 1.5 sljit on iOS without the entitlement — behavior verified

- Vendored sljit `f632608`, Apple allocator: `n64recomp:lib/sljit/sljit_src/allocator_src/sljitExecAllocatorApple.c`. On non-macOS Apple targets the `#else /* !TARGET_OS_OSX */` branch (lines 104-112) sets `SLJIT_MAP_JIT = MAP_JIT` and makes the W^X flip (`pthread_jit_write_protect_np`, line 92) a no-op — that call is macOS-only code. Allocation is `mmap(PROT_READ|PROT_WRITE|PROT_EXEC, MAP_ANON|MAP_JIT)`.
- Without the ritual, that mmap fails → `sljit_generate_code` returns NULL. For code mods the failure is **graceful**: `LiveRecompilerCodeHandle::is_good` goes false (`mods.cpp:523`) → `FailedToRecompile` error dialog → `unload_mods()` (`mods.cpp:2405-2409`, `recomp.cpp:728-748`). One hardening gap: `ShimFunction`'s ctor does not check the result (`live_generator.cpp:1969`) — a null shim would crash when called. An iOS build should gate code-mod loading up front rather than rely on the error path.

### 1.6 What is lost, what is kept, and the recommended path

| Feature | JIT-free iOS build |
|---|---|
| Full base game + all base patches/enhancements | **Kept** (AOT) |
| Texture packs (`.rtz`) | **Kept** — data-only by construction: the `.rtz` container is whitelisted to exactly one content type (`rt64.json` + images), registered at `banjo:src/main/main.cpp:793-804` with `register_mod_container_type("rtz", {texture_pack_content_type_id}, false)`; container scanning never even looks for code inside it (`nmr:librecomp/src/mod_manifest.cpp:917-939`). The handler hands the zip path to RT64's texture cache (`frontend:recompui/src/renderer/rt64_render_context.cpp:422-470`) |
| Data-only `.nrm` mods (no `mod_syms.bin`) | Kept |
| Runtime-installed **code** mods (`.nrm` live-recompiled) | **Lost** (sljit MAP_JIT + `__TEXT` detours) |
| Bundled mods compiled at app build time | Possible later via `OfflineModRecomp` + the existing `.offline.nrm` native-library path (`mods.cpp:2370-2386`; Apple extension `.dylib`, `mods.cpp:176`), **but** requires two runtime changes: a statically-linked/signed-embedded-framework variant of `DynamicLibraryCodeHandle`, and replacing `ShimFunction` sljit codegen with compiled thunks. Also `patch_func` text detours must become table-based redirection. Not v1 scope |

**Recommendation: AOT-first, no pairing ritual.** Ship install-and-play. Hide or hard-disable code-mod loading on iOS (a capability probe — one tiny MAP_JIT mmap attempt at startup — can flag "code mods available" if a user has independently enabled JIT, but nothing should depend on it, and text-patching makes even that incomplete). This matches the developer's install-and-play precedent (HarkinianPad) and forfeits nothing that the Android port's users would recognize as core: the Android port itself ships the full game, texture packs, and mods — of which only code mods would be absent on iOS.

---

## 2. Corrections to the starting facts

Every brief statement found wrong, stale, or materially incomplete, with evidence:

1. **"`librecomp/src/recomp.cpp:86` calls `live_recompiler_init()`"** — line drift: actual `nmr:librecomp/src/recomp.cpp:93` (function spans :92-98); the boot-time caller is `recomp::start()` at :836.
2. **"`librecomp/CMakeLists.txt:64`"** — actual :66. Still unconditional, but linking sljit is inert; only invocation matters.
3. **"`mods.cpp:2117` runs the base game's own patch set through it… This is not only user mods."** — Wrong in the decisive direction. Actual line :2133; it is guarded by `if (!regenlist.patched_hooks.empty())` (:2095) inside `regenerate_with_hooks`, reachable only from `load_mods` when a mod defines hooks. With zero mods it never executes. The base patch set is AOT (`RecompiledPatches/patches.c`, `banjo:CMakeLists.txt:104-107`).
4. **"whether the game boots with the mod system fully inert" (listed as unverified)** — now verified at source level: yes. No codegen path is reachable with no code mods and no hooks (§1.2-1.3).
5. **"whether texture packs are data-only or code-bearing" (listed as unverified)** — verified data-only (§1.6).
6. **The brief missed the text-segment patching dependency entirely** — `patch_func` `__TEXT` detours + the `.github/macos/ld64` max_prot wrapper (§1.4). This is the reason "JIT with StikDebug" is not a viable route to code mods, independent of sljit.
7. **"RT64 requires … Metal Argument Buffers Tier 2. Tier 2 requires GPU family Apple6, A13/A14 and later."** — Wrong on both counts at code level. Tier 2 is *optional*: `useArgumentBuffersTier2` is a capability flag (`plume:plume_metal.cpp:3845`) with a Tier-1 `MTLArgumentEncoder` fallback (`plume_metal.cpp:1700-1702, 1731-1736, 1835-1859`). The practical iOS floor implied by the code is **GPUFamilyApple3** (descriptor indexing on iOS, `plume_metal.cpp:3834`; 16-byte texel alignment, `:75-87`) — A11-class, with `bufferDeviceAddress` needing iOS 16 + Apple3 (`:3836`) and residency sets optional at iOS 18 + Apple6 (`:3837`). The README's Tier-2 phrasing is a simplification. Hardware floor is even less of a constraint than the brief assumed.
8. **"plume_metal.cpp defines PLUME_IOS…"** — the define lives in `plume:plume_metal.h:27-29` (not the .cpp); the iOS capability block is `plume:plume_metal.cpp:3833-3837` and is more complete than "two conditionals."
9. **Shader chain detail** — it is not "Metal shaders" being retargeted: the chain is HLSL → DXC (host binary) → SPIR-V → in-tree `spirv_cross_msl` host tool (MSL 2.1, argument buffers) → `xcrun -sdk macosx metal`/`metallib` → `file_to_c` embedded blobs. The macosx SDK is hardcoded in **exactly two lines**: `rt64:CMakeLists.txt:146` and `:149`. Everything upstream of those two lines is host-side and target-agnostic.
10. **"Android port … roughly 3,300 lines; android-port-plan.md … nineteen-plus sequenced tasks"** — 3,334 lines across 11 files; the plan has **21** tasks.
11. **"BanjoRecomp last commit 2026-07-26"** — HEAD `c20314c` is authored 2026-07-25 20:47 -0300 (2026-07-26 UTC). Effectively current; daily-commit cadence confirmed.
12. **"StikDebug was removed from the App Store in January 2026"** — press coverage dates the pull to December 2025 (Ubergizmo, ubergizmo.com/2025/12/stikdebug-pulled-appstore); GitHub-releases + AltStore/SideStore distribution confirmed. Immaterial to the verdict since the recommended path does not use it.
13. **Divergence the brief didn't flag:** BanjoRecomp pins N64ModernRuntime to branch `gamemodes` (`ca568b6`) while the Android port pins `main` (`3fc2e30`) — the Android fork's runtime carries API additions (save snapshot/import) and the **OSTimer fix** (§5) that upstream lacks.
14. **`OfflineModRecomp` framing** — accurate as described, but aimed at the wrong target: the base patch set never needs it (§1.3); it is the (partial) path to bundled mods only.
15. Facts checked and confirmed as stated: submodule layout and hosts (bk-decomp on GitLab — `banjo:.gitmodules`); no iOS/UIKit/Android reference in `banjo:CMakeLists.txt`/`README.md`; workflows exactly `update-pr-artifacts`, `validate-external`, `validate-internal`, `validate`; `patches/`, `patches.toml`, `banjo.us.rev0.toml`, `n_aspMain.us.rev0.toml`, `rsp/` all present; sljit pinned at `f632608`; Android port last commit 2026-07-12 with DocumentsUI save sync and dual-screen companion display; Android port has no touch controls (verified by grep — `recompinput` byte-identical to desktop, no `SDL_FINGER*` handling anywhere).

---

## 3. Current state, at file and commit granularity

### BanjoRecomp (`c20314c`)

Very active (multiple commits/day; v1.0.1 released January 2026 for Windows/Linux/macOS). One desktop target `BanjoRecompiled` (`banjo:CMakeLists.txt:145`). Platform arms: WIN32 (`:214-255`), APPLE (`:257-268` — system SDL2, `apple_bundle.cmake`, the ld64 wrapper at `:206-213`), Linux (`:270-295`). No iOS/Android arm. Build-time inputs the repo does not ship: decompressed NTSC-U 1.0 ROM (`banjo.us.v10.decompressed.z64`, pinned bk-decomp target sha1 `1fb13cad402518d3ae9a8dc4b52c5c54b2a4adc7`; `banjo:BUILDING.md:39` incorrectly lists the retail ROM sha1 `1fe1632098865f639e22c11b9a81ee8f29c75d7a`), self-built N64Recomp/RSPRecomp. CI gets the ROM from a **private secret repo** (`banjo:.github/workflows/validate.yml:39-44,84-88`). Runtime: user supplies a *retail* ROM on first launch — any of .z64/.v64/.n64 byte orders auto-detected and normalized (`nmr:librecomp/src/recomp.cpp:305-344`), XXH3-64 hash must equal `0x1B67585D56E07F8C` (`banjo:src/main/main.cpp:376`), then it is copied to `<config>/bk.n64.us.1.0.z64` (`recomp.cpp:408`). **No asset extraction ever** — the whole ROM lives in memory (`nmr:librecomp/src/pi.cpp:14`) and all cartridge DMA is served from it. Saves: raw 0x800-byte EEPROM image at `<config>/saves/bk.n64.us.1.0.bin`, event-driven writer with `.temp`/`.bak` atomic discipline (`pi.cpp:99-251`, `files.cpp:3-45`). Config: one JSON per tab in the platform config dir; macOS = `~/Library/Application Support/BanjoRecompiled` (`frontend:recompui/src/util/file.cpp:61-115`). The pinned tree now includes `COPYING`, and its project metadata identifies GPL-3.0-or-later.

### N64ModernRuntime (`ca568b6`, branch `gamemodes`)

`ultramodern` (threads/timers/audio/input/renderer glue), `librecomp` (ROM, saves, mods, boot), nested `N64Recomp` (`2b6f056`) with LiveRecomp/OfflineModRecomp and vendored sljit `f632608`. JIT topology: §1. Known platform-neutral bug: `ultramodern/src/timer.cpp:88-137` stores `OSTimer*` in a `std::set` ordered by a comparator that reads the mutable `timestamp` field — `osSetTimer` mutates it while the entry is in the set, breaking ordering invariants and producing a permanent VI-thread spin (diagnosed and fixed in the Android fork, `android:lib/N64ModernRuntime/ultramodern/src/timer.cpp:100-168`; **not** upstreamed).

### RT64 (`6f1c2d9`) and plume (`d890ac8`)

- RT64 renders through plume; graphics API "Automatic" resolves to **Metal on Apple** (`rt64:src/common/rt64_user_configuration.cpp:142-152`) — the shipped macOS build runs plume-Metal in production, which materially de-risks iOS.
- **plume already contemplates iOS**: `PLUME_IOS` (`plume:plume_metal.h:27-29`), a full iOS capability table (`plume_metal.cpp:3833-3837`), iOS texel-alignment cases (`:75-87`).
- macOS-only surface, enumerated exhaustively: (a) `plume_apple.mm:10-177` is 100% AppKit/IOKit (`NSWindow`/`NSView`/`NSScreen` window-attribute and refresh queries, `toggleFullScreen`, IORegistry vendor lookup) and backs every swap-chain size/refresh query (`plume_metal.cpp:1919, 2096-2107`); (b) exactly three macOS-only Metal/CA calls in `plume_metal.cpp`: `MTL::CopyAllDevices()` (:3782, :4196 — iOS fallback `CreateSystemDefaultDevice` already exists at :3793), `MTLDevice.location` (:3799), `CAMetalLayer.displaySyncEnabled` (:2025, :2030); (c) the `RenderWindow` on Apple is `{void* window = NSWindow*, void* view = CAMetalLayer*}` (`plume:plume_render_interface_types.h:53-62`) — BanjoRecomp supplies it via SDL (`SDL_Metal_CreateView`/`SDL_Metal_GetLayer`, `banjo:src/main/main.cpp:192-194`).
- Already iOS-clean: storage modes are Shared/Private only — `MTLResourceStorageModeManaged` never actually produced (`plume_metal.cpp:838-865`, defensive checks only at :1162-1168, :1869-1871); no CVDisplayLink — presentation is command-buffer-handler paced (`:1959-1975`); max 3 drawables (`:30`).
- Shaders: offline chain per §2 item 9; at runtime, game shaders load prebuilt `.metallib` blobs (`newLibrary(dispatch_data)`, `plume_metal.cpp:1345-1346`) specialized via `MTLFunctionConstantValues` (`:1376-1398`) with async PSO builds (`rt64:src/render/rt64_raster_shader_cache.cpp:33-105`) and an 8-permutation dynamic ubershader fallback (`rt64_raster_shader.cpp:407-492`). plume compiles only its tiny internal MSAA-resolve/clear shaders from MSL source at runtime (`plume_metal.cpp:4046, 4103`) — GPU shader compilation, legal on iOS. re-spirv is Vulkan-path-only (`rt64_raster_shader.cpp:101-174`); spirv-cross runs at build time only.
- Windowing: RT64 assumes SDL2 video + a real window/swap chain; **no headless mode exists** (grep negative). BanjoRecomp bypasses RT64's own window creation and passes its handle down (`frontend:recompui/src/renderer/rt64_render_context.cpp:225-232`, consumed `rt64:src/hle/rt64_application.cpp:120-127`). The imgui Inspector has no Metal backend (`rt64:src/gui/rt64_inspector.cpp:138-140`) — developer-mode only, acceptable gap.
- No iOS branch in any CMake (plume/rt64/root — grep negative); rt64 links IOKit (`rt64:CMakeLists.txt:460`); deployment targets hardcode macOS 10.15/11.0 (`plume:CMakeLists.txt:5-8`, `banjo:CMakeLists.txt:3-5`).
- Memory note: `preferHDR = recommendedMaxWorkingSetSize() > 512 MiB` (`plume_metal.cpp:3826`) — every modern iPhone/iPad passes, so iOS would default to RGBA16 internal framebuffers (double bandwidth) unless the port overrides `InternalColorFormat` (`rt64:src/hle/rt64_application.cpp:282-295`).

### RecompFrontend (`d0d90ba`)

- **recompui** = RmlUi 6.0 rendered *through plume* inside RT64's frame via render hooks (`frontend:recompui/src/renderer/ui_renderer.cpp:95,160`; hooks `ui_state.cpp:902-904`); UI shaders already build **MSL blobs under `__APPLE__`** (`ui_renderer.cpp:19-33`). Platform touches: SDL clipboard/cursor (RmlUi_Platform_SDL), FreeType fonts (system on Apple — must be cross-compiled for iOS), `SDL_ShowSimpleMessageBox` (UIKit-backed on iOS via SDL), and **NFD file dialogs** (`recompui/src/util/file.cpp:24-56`) — the one hard desktop-only dependency; the Android fork already ships a null-NFD backend plus a platform picker bridge. `support_apple.mm:35-68` swizzles the macOS-only `SDL_cocoametalview` class — safely no-ops on iOS (class-missing guard at :39-42).
- **recompinput** = SDL2 only: polled `SDL_GameControllerGetButton/GetAxis` + `SDL_GetKeyboardState` (`recompinput/src/input_state.cpp:145,171,221-256`), rumble (`:81-135`), gyro via SDL sensors + GamepadMotionHelpers (disabled for BK, `banjo:src/game/config.cpp:256-258`), controller DB `recompcontrollerdb.txt` (`banjo:src/main/main.cpp:703-705`), bindings persisted as `controls.json` v3 (`recompinput/src/profiles.cpp:426-576`). **Zero touch code** (no `SDL_FINGER*` anywhere).
- Input reaches the game via callbacks, not events: `osContGetReadData` → `ultramodern:src/input.cpp:153-173` → `input_callbacks.get_input = recompinput::profiles::get_n64_input` (`profiles.cpp:374-415`), registered at `banjo:src/main/main.cpp:773-778`. **This callback is the clean iOS touch-overlay seam** — wrap it and OR in synthetic buttons/stick. Pushing SDL key events would *not* reach gameplay (state is polled); menus have `recompui::queue_event` and SDL touch→mouse synthesis.

### Android port (`2966e05`)

Feature-complete with the PC version (full game, mods incl. live-recompiled code mods — Android permits JIT — texture packs, DocumentsUI save sync, dual-screen companion display, adrenotools driver loading). Architecture: vendored SDL2 2.32.10 Java glue → `BanjoSDLActivity` → native `libmain.so` exporting `SDL_main`; SDL owns the window; plume-Vulkan via `SDL_Vulkan_CreateSurface`. Paths via `APP_PROGRAM_PATH`/`APP_FOLDER_PATH` env vars consumed in `frontend` fork (`file.cpp:130-166`). ROM/mod import via SAF pickers bridged to the existing flows (ROM → `complete_android_file_dialog` → standard `recomp::select_rom`; mods → synthesized `SDL_DROPFILE` events). Save sync: app-private mirror authoritative during play; SAF folder document hydrated at launch, written back on pause via new quiesce APIs added to its N64ModernRuntime fork (`snapshot_save_file`/`import_save_file`, `android:lib/N64ModernRuntime/librecomp/src/pi.cpp:355-400`). No touch controls.

---

## 4. Android port reuse table (Section C)

Classification of all 21 tasks in `android:docs/plans/android-port-plan.md`, plus the cross-cutting fixes from `android-port-notes.md`:

| # | Android task | iOS classification |
|---|---|---|
| 1 | Record baseline desktop build state | Reusable process |
| 2 | Platform CMake option | Needs iOS equivalent (`CMAKE_SYSTEM_NAME STREQUAL "iOS"` arm) |
| 3 | Split platform-independent startup from desktop `main` (`banjo_recomp_main`) | **Reusable directly** — the fork already carries the split; iOS wrapper calls the same function |
| 4 | App skeleton (Gradle/Manifest/Activity) | Needs iOS equivalent (Xcode via `-GXcode`, Info.plist, SDL/UIKit app shell) |
| 5 | SDL2 integration path (vendored Java glue) | Needs iOS equivalent (SDL2's iOS backend + `SDL_UIKitRunApp`-style main; no Java analog needed) |
| 6 | Stub native file dialog (null-NFD backend `nfd_null.cpp` in their NFD fork) | **Reusable directly** — same null backend compiles for iOS |
| 7 | Window-creation platform guards (skip `SDL_syswm` etc.) | Needs iOS equivalent (Metal view/layer path instead of Vulkan surface) |
| 8 | App-private paths + asset staging (`APP_PROGRAM_PATH`/`APP_FOLDER_PATH`) | **Reusable in shape** — iOS: bundle `resourcePath` for program assets; Application Support (or Documents for Files visibility) for the app folder; same two env-var seams |
| 9 | preload/platform-guard hygiene | Reusable in shape (`__APPLE__` arm exists; audit for `TARGET_OS_IPHONE`) |
| 10 | Native target shape (shared lib + JNI) | Android-specific; iOS is a normal executable in an .app |
| 11 | Renderer-bypass startup mode (`BANJO_ANDROID_RENDERER_STUB` → recompui `NullRendererContext`) | **Reusable directly** — the null renderer context already exists in their frontend fork; regate for iOS |
| 12 | Audit minimal RT64 path | Reusable in shape; content diverges entirely (plume-Metal + `-sdk iphoneos` instead of Vulkan + DXC-SPIRV host split) |
| 13-15 | First configure / first compile / boot-to-launcher-without-ROM milestones | Reusable process + milestone definitions |
| 16 | ROM import flow (SAF picker → cache copy → native path → standard `select_rom`) | Needs iOS equivalent (UIDocumentPicker or Files-visible Documents scan → same `select_rom`); flow shape identical |
| 17 | Input milestone (controller DB packaging, SDL GameController) | Reusable in shape (SDL GameController sits on GCController on iOS) |
| 18 | Audio milestone (SDL audio; buffer 0x100 → 0x800 frames for Android) | Reusable in shape; expect an iOS-specific buffer retune |
| 19 | Vulkan first frame | Android-specific; the iOS analog (plume-Metal first frame) is the port's hard new work |
| 20 | Package + smoke-test APK (with ROM-artifact scan) | Needs iOS equivalent (signed .app/IPA + the same package-audit pattern HarkinianPad already has) |
| 21 | Docs/release hygiene | Reusable in shape |

Cross-cutting Android discoveries and their iOS classification:

- **OSTimer `std::set` fix — platform-neutral, must cherry-pick** (upstream still broken; §3).
- RT64 `UserPaths::detectDataPath()` `$HOME` fallback wrote an illegal path on Android (`/data/.rt64` crash) — the iOS analog (route to sandbox Application Support in `rt64:src/common/rt64_user_paths.cpp`) is required.
- App-inactive lifecycle: VI-thread pause flag + SDL audio close/reopen on focus loss — iOS equivalent is mandatory (GPU work in background = watchdog kill).
- Swapchain surface-format mismatch and plume boundless-descriptor layout mismatch produced silent black screens / driver crashes on Android — Vulkan-specific fixes, but they predict the *class* of bug to expect from plume-Metal's untested-on-iOS paths.
- Mods import via synthesized `SDL_DROPFILE` events reusing the desktop installer — directly reusable with UIDocumentPicker as the source.
- `-O0` Debug builds made performance look catastrophic (fixed with `-O2 -DNDEBUG`) — same lesson applies to iOS Debug configs.
- Clean-build handling: treat `RecompiledPatches/` as prepared inputs on the cross-compiled target, not CMake OUTPUTs (`android-port-notes.md` §clean-build) — the iOS build must copy this, since the MIPS patch toolchain runs on the host.

Not transferable: everything Vulkan (surface/swapchain/format logic, adrenotools, driver import UX), all Java/JNI/Gradle/APK work, DocumentsUI specifics, dual-screen Presentation API.

---

## 5. The Metal and plume question (Section B) — condensed answers

- **Does plume's Metal backend compile for the iOS SDK today?** No, but the gap is enumerable and small: `plume_apple.mm` (AppKit/IOKit, all of it) needs a UIKit twin; three macOS-only API calls in `plume_metal.cpp` need `PLUME_IOS` guards; no CMake iOS branch exists; rt64 links IOKit. The iOS capability table and `PLUME_IOS` machinery already exist upstream (§3).
- **Shader chain retarget:** `-sdk macosx` → `-sdk iphoneos` at exactly `rt64:CMakeLists.txt:146,149` (+ min-OS flag, + a simulator variant `-sdk iphonesimulator` if desired). DXC and `spirv_cross_msl` are host tools; the Android fork already demonstrates the host/target split under cross-compilation (`android:lib/rt64/CMakeLists.txt:57-65`). MSL 2.1 output (iOS 12+) is target-compatible.
- **Desktop-only Metal/windowing assumptions:** window-attribute/refresh/fullscreen queries all flow through the AppKit `CocoaWindow` helper — on iOS these become CAMetalLayer/UIScreen queries; SDL owns the window in BanjoRecomp's architecture and SDL-iOS provides `SDL_Metal_CreateView`/`SDL_Metal_GetLayer`, so the handle plumbing survives with a changed meaning of the `window` pointer. `displaySyncEnabled` (vsync-off) has no iOS equivalent — vsync is simply always on.
- **Runtime shader compilation:** none for game shaders (prebuilt metallibs + function constants + runtime PSO creation — all iOS-legal); plume's two tiny internal MSL-source compiles are also legal. No MTLBinaryArchive caching exists — PSO rebuild cost on every cold start, mitigated by the async cache + ubershader fallback that already exists for exactly this purpose.
- **Memory/thermal:** no large fixed GPU pools; 3 drawables max; UMA-shaped storage modes. Two iOS-specific knobs to set: disable the >512 MiB HDR auto-default (RGBA16 framebuffers) and pick a sane texture-replacement cache budget for texture packs. Real thermal behavior is unknown until a device build exists (open question Q5).

---

## 6. Blockers and risks

**Hard stops evaluated:**

1. **Prior art** — none exists. GitHub search for BanjoRecomp/Zelda64Recomp iOS: zero repos; all 61 BanjoRecomp forks enumerated (Android, UWP, macOS, 3D variants — no iOS); web searches negative. Not stopped.
2. **JIT removability** — removable; base game never uses it (§1). Not stopped.
3. **ROM data in repo** — none required. Build-time ROM comes from the builder/private CI inputs (same posture as upstream + Android port); runtime ROM is user-supplied, hash-validated, stored in-sandbox. The repo will contain no ROM data and no Nintendo assets; enforcement = the Android port's package-audit pattern + HarkinianPad's `REQUIRE_SIGNED`/prohibited-content scan pattern. Not stopped.

**Risk register (technical):**

- **R1 — plume-Metal on iOS is unexercised.** The capability table exists but nobody has run it. Likelihood of first-frame bugs: high (the Android Vulkan bring-up hit swapchain-format and descriptor-layout bugs of exactly this class). Impact: schedule, not feasibility. Mitigation: phase 1 of the plan is compile-plume-for-iOS; first-frame triage on Apple-family GPU only (no IOKit vendor path).
- **R2 — Upstream velocity.** BanjoRecomp commits daily; N64ModernRuntime/rt64/plume move too. Mitigation: pin exact SHAs like HarkinianPad does; keep iOS work as a small patch series over pinned submodules; rebase on a cadence, not continuously.
- **R3 — OSTimer freeze bug** (upstream) reproduces on iOS if not cherry-picked. Mitigation: carry the Android fork's `timer.cpp` fix from day one.
- **R4 — Watchdog/lifecycle kills.** RT64 has no background-pause concept; iOS kills apps doing GPU work in background. Mitigation: port the Android VI-pause/audio-close pattern to UIKit lifecycle events before any distribution milestone.
- **R5 — Performance/thermal unknown.** RT64 is heavier than Fast3D (HarkinianPad's renderer). A13-class floor is fine on paper (descriptor indexing at Apple3), but sustained fps/thermals are unmeasured. Mitigation: ship with HDR framebuffers off, framerate cap options already exist in the graphics menu; treat iPad (M-series) as the primary target and Apple3-A11 phones as best-effort.
- **R6 — ShimFunction null-deref hardening** if code-mod UI is not fully gated (§1.5). Mitigation: compile-time disable of code-mod loading on iOS.
- **R7 — FreeType and other deps cross-compile.** FreeType is system-linked on Apple today; iOS needs a built-from-source or prebuilt static FreeType. Low risk (routine), some toil.

**Risk register (legal/distribution):**

- **L1 — The shipped binary embeds recompiled ROM-derived code.** True of every BanjoRecomp release on every platform (the CI artifact is exactly that); the iOS IPA inherits the same posture, plus the same runtime requirement of a user-supplied retail ROM. This is the accepted community posture (Zelda64Recomp/BanjoRecomp have distributed such binaries publicly since January 2026 without takedown found), but it is not risk-free and an IPA adds nothing new to it. Mitigation: source-first distribution; sideload docs; never bundle the ROM or weaken the hash gate.
- **L2 — RecompFrontend lacks a project-level license** at the pinned revision. BanjoRecomp identifies GPL-3.0-or-later, N64ModernRuntime includes GPLv3 text, and RT64 is MIT, but the nested GamepadMotionHelpers MIT notice does not license RecompFrontend itself. Mitigation: obtain authoritative upstream clarification before any binary or third-party source-bundle redistribution; source-only until then.
- **L3 — Distribution constraints.** Same as HarkinianPad: personal-signing sideload always works; AltStore PAL is region-limited; TestFlight/App Store are not goals. An unsigned-IPA release with user-side signing is viable (documented precedent in `harkinianpad:docs/INSTALL_IPA.md`).

---

## 7. Scope comparison (Section F)

**Against the libultraship family:** HarkinianPad's investigation found libultraship already contained a CI-exercised iOS build path — `__IOS__` compile arms, an iOS dependency file, an Xcode toolchain, iOS-correct sandbox paths — so that port was "the completion of one upstream started," with the remaining work concentrated in the app layer (`harkinianpad:docs/ios-feasibility-and-implementation-plan.md` §A). BanjoRecomp has **none of that**: zero iOS references anywhere in the stack, a renderer (RT64/plume) an order of magnitude heavier than Fast3D, a shader pipeline that must be retargeted, and a runtime with its own threading/timer model. Honest sizing: this project is **several times larger** than HarkinianPad was — HarkinianPad's engine-side work was two link fixes plus lifecycle/scaling polish; this one requires bringing up an unexercised Metal RHI path on a new OS, a new app shell, and the first touch-control layer anyone has built for this stack. The Android port proves the runtime and frontend port cleanly to a mobile OS, which removes the largest unknowns — but the Android port also had JIT and Vulkan available, and iOS has neither.

**The counterargument, stated plainly:** solving RT64 + plume on iOS once opens **every** N64Recomp title. Zelda64Recomp (Majora's Mask, with Ocarina of Time in development), BanjoRecomp, and every future N64Recomp port share exactly this runtime and renderer. Nobody has done it; no one is publicly working on it (§6 hard stop 1). The plume-Metal gap list is short and the capability scaffolding already exists upstream. Unlike the libultraship family — where iOS work rides on an existing lane — this creates the lane, and the deliverable is not "Banjo on iPad" but "the N64Recomp stack runs on iOS," with Banjo as the first shipping proof. That, plus the favorable JIT resolution (install-and-play with no ritual), is why the verdict is *recommended* and not merely *feasible*.

---

## 8. Open questions

1. **Does plume-Metal actually render correctly on an iOS device first try?** Unknown; the Android experience predicts format/capability edge bugs. Resolved by: phase-1 compile + first-frame device test (the plan's smallest end-to-end proof).
2. **Real performance and thermals on target hardware** (A13 iPhone vs M-series iPad; HDR off; specialized-PSO compile hitching on cold start). Resolved by: measurement at the first-playable milestone; MTLBinaryArchive caching is the known follow-up if hitching is objectionable.
3. **SDL2-iOS behavioral details for this stack**: `SDL_Metal_GetLayer` semantics on iOS (returns the `CAMetalLayer` of `SDL_uikitmetalview` — expected to work, unexercised here), audio buffer sizing on AVAudioSession, GameController mapping coverage vs `recompcontrollerdb.txt`. Resolved by: bring-up testing; all have Android-proven fallback shapes.
4. **Upstream reception**: would N64ModernRuntime/rt64/plume accept iOS patches (PLUME_IOS completion, UIKit window helper, timer fix upstreaming)? Unknown. Resolved by: asking after a working prototype exists; until then keep everything as pinned-fork patches (HarkinianPad's model — publication repo owns all changes, upstreams are read-only inputs).
5. **Simulator viability** for plume-Metal (Metal on the iOS Simulator has feature gaps; argument-buffer behavior differs). Resolved by: try early in phase 1; treat device as reference, simulator as best-effort (HarkinianPad ultimately got full simulator parity, but on a far simpler renderer).
6. **Minimum OS/device floor to commit to**: code says Apple3 GPU + iOS 16 for `bufferDeviceAddress`-dependent features; picking iOS 16 as the app floor simplifies the matrix. Resolved by: decision at plan time (recommended: iOS 16.0, A13+ officially, Apple3 best-effort).
7. **Whether any upstream change lands text-patch-free mod redirection** (e.g. lookup-table-based replacements), which would reopen the bundled/code-mod question on iOS. Watch `N64Recomp/N64ModernRuntime` (`use_lookup_for_all_function_calls` exists for regenerated contexts, `nmr:librecomp/src/mods.cpp:2028`; not exposed for base recompilation today).

---

**Gate decision:** verdict is *feasible and recommended* → proceeding to Stage 2 (implementation plan) per the brief.
