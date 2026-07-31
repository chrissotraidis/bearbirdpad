# BearBirdPad status

Updated 2026-07-31. Current phase: stable physical-device development build
and free unsigned developer preview.

## Current result

BearBirdPad builds as a universal arm64 iPhone/iPad app with an iOS 16.0
deployment target. The regular play path is stable in current owner testing:
supported-ROM loading, Metal rendering, touch gameplay, settings, saves,
in-place updates, and separate phone/tablet control layouts are working.

The `v0.1.0-preview.1` unsigned IPA is a deterministic, ROM-free developer
preview. Its SHA-256 is
`275aefb38924f5d1edd1c7361ef47df5bc961e005eade51954d7cfe647ab6b24`.
It includes the project rights notices and 87 discovered third-party license
files and requires user-side signing plus a legally acquired supported ROM.
The exact archive passed local payload and reproducibility checks. It was not
freshly re-signed for another device install in this release session because
the configured Xcode account could not create a new provisioning profile; the
same source app had already been signed, installed, launched, and exercised on
the iPad and iPhone listed below.

The latest focused fixes keep the persistent `•••` menu button inside the
active safe area and scale iOS pointer events from UIKit/SDL logical
coordinates into the Retina pixel coordinate space expected by
RecompFrontend. Together they fix the clipped menu and unresponsive
high-DPI menu taps observed on physical hardware.

## Physical-device evidence

| Device | OS | Verified |
|---|---|---|
| 12.9-inch iPad Pro (6th generation), `iPad14,5` | iPadOS 26.5.2 | Signed install, local ROM loading, gameplay, touch controls, menu access, save creation/reload, save export, settings persistence, and in-place update |
| iPhone 14, `iPhone14,7` | iOS 26.5.2 | Signed install, local ROM loading, gameplay, touch controls, safe-area menu placement, imported iPad save, phone-default layout restoration, and in-place update |

Both devices used the same universal application bundle. The iPad save was
backed up before the iPhone transfer, then copied into the iPhone app
container with its `.bak` companion. The original iPad save remained intact.

## Current feature evidence

| Area | Evidence |
|---|---|
| Source graph | Pinned BanjoRecomp, N64ModernRuntime, RT64, Plume, RecompFrontend, and nested dependencies replay through `scripts/fetch-sources.sh` |
| Builds | Release Simulator and physical-device app targets have completed locally |
| Rendering | Plume/RT64 Metal output runs on Simulator, physical iPad, and physical iPhone |
| ROM handling | NTSC-U 1.0 validation accepts `.z64`, `.v64`, and `.n64`; stored ROM loading reaches gameplay |
| Touch | Full N64 overlay, simultaneous touches, duplicated-Z reference counting, editor, optional controls, and persistent menu |
| Layout persistence | Normalized `phone-v1` and `tablet-v1` preferences survive relaunch and remain independent |
| Pointer input | Logical SDL pointer coordinates are scaled to the drawable's Retina pixel space on iOS |
| Saves | Primary and `.bak` save files load after relaunch, transfer between devices, and survive in-place installs |
| Mods | `.rtz` texture packs can be imported through Files or the Mods picker |
| Packaging | App audit rejects ROM paths/digests and generated-source markers; signed mode verifies the signature and provisioning Team ID |
| Repository safety | Local gate rejects proprietary/game data, generated source, packaged output, signing material, large files, likely credentials, invalid patches, and broken local documentation links |

## Remaining release checks

These are breadth and distribution gates, not known blockers in the regular
touch play path:

- complete the physical controller reconnect, rumble, and model matrix;
- exercise headphones, Bluetooth audio, calls/Siri, and longer interruption
  recovery;
- record a repeatable FPS, hitch, memory, and thermal matrix on the target
  device range;
- re-sign and update-install the exact final distributable IPA after the local
  Xcode account can provision `com.chrissotraidis.bearbirdpad`, then extend
  validation to additional physical iPhone and iPad models; and
- obtain authoritative clarification of RecompFrontend's missing project-level
  license before paid access, commercial licensing, or official-store
  distribution.

The GitHub Actions workflow is configured to build a ROM-free Simulator stub,
audit it, and upload a proof artifact. Hosted jobs are currently prevented
from starting by the repository owner's GitHub Actions billing/spending state;
this is an account-level limitation rather than a source or build failure.

## Publication boundary

No ROM, generated recompilation input, save, texture pack, device backup,
provisioning profile, certificate, signed application, or IPA belongs in Git.
Every public IPA must pass [`docs/RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md)
on the exact tagged artifact. The free unsigned developer preview follows
BanjoRecomp's public binary model while clearly disclosing RecompFrontend's
unresolved project-level license; that uncertainty still blocks paid access,
commercial licensing, and official-store distribution.
