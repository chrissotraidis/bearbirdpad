# Status — updated 2026-07-28, iteration 5

Phase: 0 — Pinned sources, host tools, macOS baseline

Done this iteration: blocker protocol invoked after the third consecutive generated-source preparation failure — evidence: `find ref -maxdepth 1 -type f` → the same single ROM file is present; `./scripts/prepare-generated.sh 'ref/Banjo-Kazooie (U) [!].z64'` → rejected before decompression with expected XXH3-64 `1B67585D56E07F8C`, found `D287BE61F6682734` (failure 3/3).

Next goal: BLOCKED until the invalid file in `ref/` is replaced with a legally owned Banjo-Kazooie NTSC-U retail dump; resume with `scripts/prepare-generated.sh <path>`.

HUMAN-VERIFY queue: none.

Blockers: BLOCKED — Phase 0 generated sources and the macOS baseline cannot proceed because the only ROM in `ref/` is not the required NTSC-U retail image. Evidence: three consecutive runs produced the same runtime hash mismatch; the pinned compressor identity check also expects NTSC-U MD5 `b29599651a13f681c9923d69354bf4a3`, while this already-big-endian 8 MiB input is `4bc8449426ca1c72b7b0bb1323dad47f`. Tried: verified the runtime's exact XXH3 implementation and byte-order normalization, built the pinned host tools, and reran the guarded preparation path without modifying or exporting the ROM. Decision forced: stop before Phase 1 because Phase 0 acceptance is not green. Recommendation and recovery: replace the local input with a valid dump that normalizes to XXH3-64 `1B67585D56E07F8C`; there is no sanctioned fallback, and no ROM will be searched for or downloaded.

ref/ additions: none.

Deviations from plan: 2026-07-28 — bk-decomp's pinned n64splat submodule appears worktree-dirty immediately after checkout because upstream tracks one CRLF file while declaring `text eol=lf`; the diff is line-ending-only and no source logic was changed.
