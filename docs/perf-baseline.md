# iOS performance baseline

Status: automatable Phase 8 evidence complete; physical-device results are `HUMAN-VERIFY`.

This document is the measurement contract for the commit that contains it. Do not treat Simulator numbers as iPhone or iPad performance: Simulator uses the Mac CPU, memory system, and graphics stack.

## Shipping defaults

These defaults apply only when `graphics.json` has no saved value. Upgrades preserve the user's existing settings.

| Setting | iOS first boot | Evidence |
|---|---|---|
| Internal color format | Standard | High Precision Framebuffer defaults to `Off`, which maps to RT64 `Standard` |
| MSAA | Off | iOS-only frontend default is `Antialiasing::None` |
| Resolution scale | 1.0 | iOS-only resolution default is `Original`; downsampling defaults to `Off` |
| Framerate cap | Display | Existing frontend default |

Desktop behavior is unchanged: its resolution default remains `Auto` and its MSAA default remains `MSAA2X`.

The device Release build uses `-O3 -DNDEBUG` for C and C++, exceeding the Phase 8 `-O2` minimum. The verified toolchain baseline is Xcode 26.6 (17F113), iPhoneOS SDK 26.5, deployment target iOS 16.0, arm64.

Clean-install proxy: the Release app was installed on a temporary iPad Pro 11-inch (M4), iOS 18.5 Simulator. Its first generated `graphics.json` recorded `hpfb_option=Off`, `msaa_option=None`, `res_option=Original`, `ds_option=0`, and `rr_option=Display`; the file SHA-256 was `e6d6aa4600553ee02e0aee3e1e2010ff99d3312d5d1ec1eaa71ed79812b41214`. The temporary device was deleted after capture. This proves default selection, not device performance.

## Required device matrix

Enter actual measurements only from signed Release builds on physical hardware.

| Device | OS | Commit | Spiral Mountain steady FPS | Mumbo's Mountain steady FPS | Worst cold-start hitch | Peak footprint | 20-minute soak | Jetsam/watchdog |
|---|---|---|---:|---:|---:|---:|---|---|
| M-series iPad, primary | `HUMAN-VERIFY` | `HUMAN-VERIFY` | `HUMAN-VERIFY` | `HUMAN-VERIFY` | `HUMAN-VERIFY` | `HUMAN-VERIFY` | `HUMAN-VERIFY` | `HUMAN-VERIFY` |
| A13 device, floor | `HUMAN-VERIFY` | `HUMAN-VERIFY` | `HUMAN-VERIFY` | `HUMAN-VERIFY` | `HUMAN-VERIFY` | `HUMAN-VERIFY` | `HUMAN-VERIFY` | `HUMAN-VERIFY` |

Acceptance is a stable 60 FPS, or the selected display cap when lower, on the primary iPad; no jetsam or watchdog termination; and no sustained serious/critical thermal state. Record median, 1% low, and minimum FPS rather than a visual estimate.

## Reproducible protocol

1. Build with `scripts/build-ios.sh --device --app --config Release`, sign, install, and record `git rev-parse HEAD`, device model, OS, display refresh rate, and the four defaults above.
2. Reboot the device for the first cold-start run. Start a `Game Performance` trace, launch the app, select the retail ROM, and capture through the first controllable frame. Repeat three force-quit/cold-launch runs. Record the longest frame and visible hitch duration.
3. Capture five minutes in Spiral Mountain and five minutes in Mumbo's Mountain after two minutes of warm-up in each area. Do not open menus during the sample. Record median FPS, 1% low, minimum FPS, CPU/GPU frame time, and peak resident/dirty memory.
4. Start from a cool device at at least 50% charge, disconnect the debugger after recording begins, and play continuously for 20 minutes in Mumbo's Mountain. Record FPS and memory at minutes 0, 5, 10, 15, and 20 plus every thermal-state transition.
5. After the soak, inspect Xcode device logs for jetsam, watchdog, GPU restart, or Metal validation failures. Attach the `.trace` filenames and crash-log result to the table or release evidence.

Xcode 26.6 exposes the required `Game Performance`, `Metal System Trace`, `Game Memory`, `App Launch`, and `Power Profiler` templates. A repeatable CLI capture is:

```sh
xcrun xctrace record \
  --template 'Game Performance' \
  --device '<physical-device-name-or-UDID>' \
  --time-limit 5m \
  --attach BanjoRecompiled \
  --output '<device>-<area>.trace'
```

Use `Metal System Trace` for the three cold-start runs, `Game Memory` to confirm the peak footprint, and `Power Profiler` for the 20-minute soak. Keep traces outside Git; they can contain device and path metadata.

## PSO cache decision

DD5 (`MTLBinaryArchive`) remains deferred. The renderer already builds specialized PSOs asynchronously and has a dynamic ubershader fallback. Adding a persistent archive without physical cold-start hitch evidence would add lifecycle and invalidation complexity without a demonstrated gain. Trigger DD5 only if all three physical cold-start traces show a user-visible hitch attributable to PSO compilation; record the frame duration and shader/PSO evidence first.
