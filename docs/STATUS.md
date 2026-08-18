# BearBirdPad status

Updated 2026-08-18. Current phase: stable physical-device development build
and free unsigned developer preview.

## Current result

BearBirdPad builds as a universal arm64 iPhone/iPad app with an iOS 16.0
deployment target. The regular play path is stable in current owner testing:
supported-ROM loading, Metal rendering, touch gameplay, settings, saves,
in-place updates, and separate phone/tablet control layouts are working.

The `v0.1.0-preview.2` unsigned IPA is a deterministic, ROM-free developer
preview. Its SHA-256 is
`8e39e264a6ef096661ed7e75eaa5028513e3091a20464197877d8e60b249bcf9`.
It includes the project rights notices and 87 discovered third-party license
files and requires user-side signing plus a legally acquired supported ROM.
The exact archive passed local payload and reproducibility checks. A separate
development-signed build with the same bundle ID and signing team was installed
in place on the iPad, then launched to the rendered title menu.

BearBirdPad uses RecompFrontend's SDL2 `SDL_GameController` backend. The prior
event-only ownership path opened controller handles on add, erased state on a
remove event without closing the handle, did not validate attachment while
polling, and did not reconcile on foreground resume. A missed removal during
sleep could therefore leave stale non-null ownership and held input.

Build 2 adds a compact four-slot identity helper at that existing seam. It
enumerates current SDL game controllers, validates attachment and instance
identity, closes stale handles, fills the first free slot deterministically,
and reads gameplay input only from attached handles. Reconciliation runs at
startup, add/remove/remap events, foreground resume, and a bounded one-second
active check. Existing mappings and touch preferences are unchanged, and SDL
is never restarted.

## Physical-device evidence

| Device | OS | Verified |
|---|---|---|
| 12.9-inch iPad Pro (6th generation), `iPad14,5` | iPadOS 26.6 | Build 2 same-team in-place install, live PID, SDL/UIKit and Metal initialization, existing-ROM title-menu render, foreground controller reconciliation, and byte-identical ROM/save/controller/touch preferences after readback |
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
| Controllers | Deterministic regression covers missed removal with held button/axis input, neutral release, sole return to player 1, an additional controller in player 2, preservation of an unaffected slot, and foreground reconciliation |
| Saves | Primary and `.bak` save files load after relaunch, transfer between devices, and survive in-place installs |
| Mods | `.rtz` texture packs can be imported through Files or the Mods picker |
| Packaging | App audit rejects ROM paths/digests and generated-source markers; signed mode verifies the signature and provisioning Team ID |
| Repository safety | Local gate rejects proprietary/game data, generated source, packaged output, signing material, large files, likely credentials, invalid patches, and broken local documentation links |

## Remaining release checks

These are breadth and distribution gates, not known blockers in the regular
touch play path:

- physically exercise Bluetooth disconnect/reconnect, wired
  disconnect/reconnect, natural sleep/wake, active and foreground return,
  held-input release, overlay restoration, full mapping, rumble, and
  two-controller slot preservation;
- exercise headphones, Bluetooth audio, calls/Siri, and longer interruption
  recovery;
- record a repeatable FPS, hitch, memory, and thermal matrix on the target
  device range;
- re-sign the unsigned release IPA with the same application identity before a
  future device install, and extend validation to additional physical iPhone
  and iPad models; and
- obtain authoritative clarification of RecompFrontend's missing project-level
  license before paid access, commercial licensing, or official-store
  distribution.

The GitHub Actions workflow builds a ROM-free Simulator stub, audits it, and
uploads a proof artifact. Both the push and pull-request runs for Preview 2
completed successfully.

## Publication boundary

No ROM, generated recompilation input, save, texture pack, device backup,
provisioning profile, certificate, signed application, or IPA belongs in Git.
Every public IPA must pass [`docs/RELEASE_CHECKLIST.md`](RELEASE_CHECKLIST.md)
on the exact tagged artifact. The free unsigned developer preview follows
BanjoRecomp's public binary model while clearly disclosing RecompFrontend's
unresolved project-level license; that uncertainty still blocks paid access,
commercial licensing, and official-store distribution.
