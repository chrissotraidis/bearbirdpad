# Status — updated 2026-07-28, iteration 2

Phase: 0 — Pinned sources, host tools, macOS baseline

Done this iteration: Phase 0 host tools built reproducibly into `build-host/bin/` — evidence: `./scripts/build-host-tools.sh` → `N64Recomp`, `RSPRecomp`, `file_to_c`, and `spirv_cross_msl` are Release arm64 Mach-O executables; CLI smoke → both recompilers print usage, `file_to_c` generated C that `cc` compiled, and `spirv_cross_msl` enforced its input/output contract; second `cmake --build` → `ninja: no work to do`.

Next goal: normalize and verify the retail ROM, then generate the pinned AOT game and RSP sources with an idempotent `scripts/prepare-generated.sh`.

HUMAN-VERIFY queue: none.

Blockers: none.

ref/ additions: none.

Deviations from plan: 2026-07-28 — bk-decomp's pinned n64splat submodule appears worktree-dirty immediately after checkout because upstream tracks one CRLF file while declaring `text eol=lf`; the diff is line-ending-only and no source logic was changed.
