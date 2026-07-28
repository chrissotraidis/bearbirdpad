# Reference material

Read-only reference inputs for the banjopad iOS port. Nothing in this folder is a build input, and **everything here except this README is gitignored** — the contents stay local and are never committed or pushed.

- **The original game ROM lives here**: place your legally owned Banjo-Kazooie NTSC-U v1.0 retail dump in this folder (`.z64`/`.v64`/`.n64`, any byte order — the tooling normalizes it). A complete dump is exactly 16 MiB (16,777,216 bytes), normalizes to XXH3-64 `1B67585D56E07F8C`, and has big-endian MD5 `b29599651a13f681c9923d69354bf4a3`. It is validated during Phase 0 (see [../docs/banjo-ios-loop.md](../docs/banjo-ios-loop.md)) and staged into `sources/` locally for the recompilers. A short dump must be re-dumped, not padded, because the missing range contains game data. The ROM must never be committed, pushed, or uploaded.
- **Cloned reference repos** (the Android port, upstream HEADs, texture packs / graphics mods, decomp material) also go here — the build loop fetches them as needed and logs each one below with URL, commit, and purpose.

Fetched 2026-07-28 by `scripts/fetch-references.sh`:

- **HarkinianPad** — local checkout at `/Users/chrissotraidis/GitHub/harkinianpad` @ `01523225a3e9d32348e25d608dcb2d391dab5310`; completed iOS shell, packaging-audit, install, and touch-control templates.
- **BanjoRecomp-Android** — <https://github.com/AurelioB/BanjoRecomp-Android.git> @ `2966e05b808afdf7fb82cb3f07397aa9383b02f1`; structural map and source of the D13/D14, null-NFD, and renderer-stub patterns.
- **N64Recomp** — <https://github.com/N64Recomp/N64Recomp.git> @ `ffb39cdad1da5de07eaaa48bd1db4a89a7986771`; current upstream read-only check for recompiler and iOS/JIT-related drift.
- **N64ModernRuntime** — <https://github.com/N64Recomp/N64ModernRuntime.git> @ `ae1ffbb909d9f93c88c41830deb539f7feef5ed2`; current upstream read-only check for timer, save, and mobile-runtime drift.
- **rt64** — <https://github.com/rt64/rt64.git> @ `6f1c2d99a4ea571c139f449c326fd176ba8f3496`; current upstream read-only check for plume-Metal and shader-toolchain drift.

All reference-clone push URLs are set to `DISABLED`. Upstream pins and per-file citations live in the feasibility document's tree table; build inputs are the pinned checkouts under `sources/`, never these reference clones.
