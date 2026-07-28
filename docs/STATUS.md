# Status — updated 2026-07-28, iteration 1

Phase: 0 — Pinned sources, host tools, macOS baseline

Done this iteration: pinned source and baseline reference checkouts fetched safely — evidence: `./scripts/fetch-sources.sh` → `Pinned sources are ready`; BanjoRecomp `c20314c`, N64ModernRuntime `ca568b6`, N64Recomp `2b6f056`, rt64 `6f1c2d9`, plume `d890ac8`, RecompFrontend `d0d90ba`, bk-decomp `351ca15`, and BanjoRecompSyms `6820055` verified; recursive source push-URL audit → no URL other than `DISABLED`; `git status --short --ignored` → `sources/`, reference clones, and the retail ROM are ignored.

Next goal: build the Phase 0 host tools into `build-host/bin/`.

HUMAN-VERIFY queue: none.

Blockers: none.

ref/ additions: BanjoRecomp-Android @ `2966e05` — Android structural map and D13/D14 patch source; N64Recomp @ `ffb39cd` — current upstream recompiler drift check; N64ModernRuntime @ `ae1ffbb` — current upstream runtime drift check; rt64 @ `6f1c2d9` — current upstream renderer drift check; local HarkinianPad @ `0152322` — iOS shell and packaging templates.

Deviations from plan: 2026-07-28 — bk-decomp's pinned n64splat submodule appears worktree-dirty immediately after checkout because upstream tracks one CRLF file while declaring `text eol=lf`; the diff is line-ending-only and no source logic was changed.
