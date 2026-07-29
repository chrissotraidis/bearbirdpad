# BanjoPad

Banjo-Kazooie on iPhone and iPad through a native iOS port of [BanjoRecomp](https://github.com/BanjoRecomp/BanjoRecomp).

BanjoPad keeps the upstream recompiled game and Metal renderer, then adds the iOS shell: Files-based ROM and texture-pack import, landscape touch controls, MFi controller support, safe suspend/resume, Files-visible saves, conservative mobile graphics defaults, and ROM-free packaging.

## What works

- Native arm64 device and Apple-silicon Simulator builds
- Plume/RT64 Metal rendering
- Retail NTSC-U 1.0 ROM validation and `.z64` / `.v64` / `.n64` import
- `.rtz` texture packs through Files or the Mods picker
- MFi/PS/Xbox input plus simultaneous multi-touch controls
- Save/config flush, audio recovery, and background-safe rendering
- Audited unsigned IPA packaging

The app never includes a ROM. You must provide your own complete, legally obtained Banjo-Kazooie NTSC-U 1.0 cartridge dump on first launch.

See [Texture packs](docs/TEXTURE-PACKS.md) for installation and the currently tested recommendation.

## Build

Start with [Building BanjoPad for iOS](docs/BUILDING-IOS.md). The complete local path is:

```sh
scripts/fetch-sources.sh
scripts/build-host-tools.sh
scripts/prepare-generated.sh "/absolute/path/to/Banjo-Kazooie (USA).n64"
scripts/build-ios.sh --device --app --config Release
scripts/package-ios.sh
```

Pinned upstream source trees and ROM-derived build outputs live only in ignored local directories. The public CI path builds a small ROM-free Simulator stub, applies the complete patch graph, audits the app bundle, and packages a proof artifact.

## Verification status

[STATUS.md](docs/STATUS.md) is the evidence ledger and physical-device queue. [perf-baseline.md](docs/perf-baseline.md) defines the M-series iPad and A13 measurement contract. Hosted CI is supplemental and does not block local release work; the `v0.1.0` tag waits for the signed physical-device package gate.
