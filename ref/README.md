# Reference material

Read-only reference inputs for the banjopad iOS port. Nothing in this folder is a build input.

- **HarkinianPad** — completed native iOS/iPadOS port of Ship of Harkinian by the same developer; local checkout at `~/GitHub/harkinianpad`. Its `docs/` (feasibility/implementation plan, touch-controls design, BUILDING, INSTALL_IPA, RELEASE_CHECKLIST) are the templates for this project's app shell, signing, Files integration, packaging audit, and touch-control design.
- **BanjoRecomp-Android** (`AurelioB/BanjoRecomp-Android`) — the structural map for this port; see its `docs/plans/` (~3.3k lines). Analyzed at commit `2966e05` in [../docs/banjo-ios-feasibility.md](../docs/banjo-ios-feasibility.md) §4.
- Upstream pins and per-file citations live in the feasibility document's tree table; fetch scripts (Phase 0 of the implementation plan) will clone pinned sources into `sources/` (gitignored), not here.
