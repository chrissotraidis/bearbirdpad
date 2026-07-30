# Texture packs

BearBirdPad supports RT64 data-only texture packs in `.rtz` format. Packs contain replacement images and metadata; they do not add executable code.

## Install

1. Obtain a Banjo-Kazooie RT64 `.rtz` pack from its author.
2. In Files, place it in **On My iPhone/iPad → BearBirdPad → BanjoRecompiled → mods** while BearBirdPad is in the background. You can also use **Mods → Install** in the launcher.
3. Return to BearBirdPad. The app rescans the folder immediately.
4. Open **Mods**, enable the pack, and start the game.

Keep packs outside the app bundle and repository. BearBirdPad does not redistribute community pack data.

## Tested recommendation

**[BK Reloaded v0.1.1 (RT64)](https://evilgames.eu/files/texture-packs/bk-reloaded-v0.1.1-rt64.rtz)** by GhostlyDark is the current tested baseline.

- SHA-256: `1cbd5d2301f98947ea8e27a90796c16f56884a88461f28de2b85a34f5763e65f`
- Manifest ID: `BK-Reloaded`
- Description: an HD texture replacement for Banjo-Kazooie
- Verified locally on iPhone 16 Pro and iPad Pro 11-inch (M4), iOS 18.5 Simulators: background-folder discovery, enabled/disabled state, runtime load, and live rendering

Physical-device visual quality, memory, and thermal behavior remain part of the [`HUMAN-VERIFY` queue](STATUS.md).
