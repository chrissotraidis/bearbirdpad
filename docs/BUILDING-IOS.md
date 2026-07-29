# Building BanjoPad for iOS

BanjoPad builds BanjoRecomp as a native arm64 iPhone/iPad app. The repository never contains or downloads Banjo-Kazooie ROM data. You must supply your own complete NTSC-U 1.0 cartridge dump for the local full-game build and again on first launch.

## Verified toolchain

- macOS on Apple silicon
- Xcode 26.6 (17F113), iPhoneOS SDK 26.5
- CMake 3.24 or newer, Ninja, Git, Rust/Cargo, and standard macOS command-line tools
- iOS 16.0 deployment target

Install the command-line prerequisites with Homebrew if needed:

```sh
brew install cmake ninja rust
```

Install the iOS platform and Metal toolchain from Xcode Settings > Components. Accept the Xcode license and open Xcode once before using command-line builds.

## Full local build

From the repository root:

```sh
scripts/fetch-sources.sh
scripts/build-host-tools.sh
scripts/prepare-generated.sh "/absolute/path/to/Banjo-Kazooie (USA).n64"
scripts/build-ios.sh --device --app --config Release
```

`prepare-generated.sh` accepts `.z64`, `.v64`, or `.n64` byte order, requires the complete 16 MiB NTSC-U 1.0 image, verifies retail XXH3-64 `1B67585D56E07F8C`, and verifies the decompressed build input SHA-1 `1fb13cad402518d3ae9a8dc4b52c5c54b2a4adc7`. It writes only under ignored `sources/` and `build-*` paths.

The unsigned device app is:

```text
build-ios-app-device/Release/BanjoRecompiled.app
```

The build-time ROM and generated source files are not copied into the app. BanjoPad still asks the user to import a legally obtained retail ROM on first launch; the same runtime hash gate validates it.

## Simulator

Build the arm64 Simulator app:

```sh
scripts/build-ios.sh --simulator --app --config Release
xcrun simctl install booted build-ios-app-simulator/Release/BanjoRecompiled.app
xcrun simctl launch booted com.chrissotraidis.banjopad
```

Simulator proves UI, import, rendering, input, and lifecycle behavior. It does not provide valid iPhone/iPad FPS, memory, thermal, speaker, controller, interruption, or watchdog evidence; use the physical matrix in [perf-baseline.md](perf-baseline.md) and [STATUS.md](STATUS.md).

## Personal-team signing and device install

Find the Team ID shown for your Apple account in Xcode, then build with it:

```sh
DEVELOPMENT_TEAM=XXXXXXXXXX \
  scripts/build-ios.sh --device --app --config Release
```

Connect and trust the device, enable Developer Mode, then install the signed app:

```sh
xcrun devicectl device install app \
  --device '<device-name-or-UDID>' \
  build-ios-app-device/Release/BanjoRecompiled.app
```

Before distribution, require both a valid signature and embedded provisioning profile:

```sh
REQUIRE_SIGNED=1 \
  scripts/package-audit.sh build-ios-app-device/Release/BanjoRecompiled.app
```

Free personal-team provisioning expires and has capability limits. Rebuild or re-sign when the profile expires.

## IPA packaging

Create the ROM-free unsigned archive:

```sh
scripts/package-ios.sh \
  build-ios-app-device/Release/BanjoRecompiled.app \
  build/release/BanjoPad-0.1.0-unsigned.ipa
```

The script audits the app before wrapping `Payload/BanjoRecompiled.app`, normalizes archive timestamps and entry order, verifies the ZIP, and prints its SHA-256. Packaging the same app bundle twice therefore produces the same IPA bytes. An unsigned IPA cannot install directly: a personal-team workflow or sideloading tool must sign it for the destination device. To package an already signed app, set `REQUIRE_SIGNED=1`; the audit will reject a missing/invalid signature or provisioning profile.

Never add a ROM, generated source, save, mod, provisioning profile, certificate, or Instruments trace to Git.

## ROM-free CI mode

CI intentionally cannot build the full game without private generated inputs. Its public path proves the pinned source/patch graph, host tools, iOS toolchain, bundle generation, package audit, and archive creation with a small Metal/SDL stub:

```sh
scripts/fetch-sources.sh
scripts/build-host-tools.sh
scripts/build-ios.sh --simulator --stub --config Release
scripts/package-audit.sh \
  build-ios-ci-stub-simulator/Release-iphonesimulator/BanjoPadCIStub.app
```

The full-game Release build remains a local, user-ROM-derived operation. CI must never substitute, download, or publish those inputs.
