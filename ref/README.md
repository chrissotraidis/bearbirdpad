# Reference material

Read-only reference inputs for the banjopad iOS port. Nothing in this folder is a build input, and **everything here except this README is gitignored** — the contents stay local and are never committed or pushed.

- **The original game ROM lives here**: place your legally owned Banjo-Kazooie NTSC-U retail dump in this folder (`.z64`/`.v64`/`.n64`, any byte order — the tooling normalizes it). It is validated by hash during Phase 0 (see [../docs/banjo-ios-loop.md](../docs/banjo-ios-loop.md)) and staged into `sources/` locally for the recompilers. It must never be committed, pushed, or uploaded.
- **Cloned reference repos** (the Android port, upstream HEADs, texture packs / graphics mods, decomp material) also go here — the build loop fetches them as needed and logs each one below with URL, commit, and purpose.

- **HarkinianPad** — completed native iOS/iPadOS port of Ship of Harkinian by the same developer; local checkout at `~/GitHub/harkinianpad`. Its `docs/` (feasibility/implementation plan, touch-controls design, BUILDING, INSTALL_IPA, RELEASE_CHECKLIST) are the templates for this project's app shell, signing, Files integration, packaging audit, and touch-control design.
- **BanjoRecomp-Android** (`AurelioB/BanjoRecomp-Android`) — the structural map for this port; see its `docs/plans/` (~3.3k lines). Analyzed at commit `2966e05` in [../docs/banjo-ios-feasibility.md](../docs/banjo-ios-feasibility.md) §4.
- Upstream pins and per-file citations live in the feasibility document's tree table; fetch scripts (Phase 0 of the implementation plan) will clone pinned sources into `sources/` (gitignored), not here.
