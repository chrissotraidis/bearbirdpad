# Status — updated 2026-07-28, iteration 6

Phase: 0 — Pinned sources, host tools, macOS baseline

Done this iteration: identified the actionable ROM failure and added an early, safe diagnostic — evidence: N64 header → `NBKE`, revision `00`, and expected NTSC-U v1.0 header CRC `A4BF9306 BF0CDFD1`; `stat` → 8,388,608 bytes, exactly half the required 16,777,216 bytes; pinned compressor source → required game overlays extend through `0xFDAA30`, beyond the local file; `scripts/prepare-generated.sh` now rejects short inputs with a re-dump instruction and warns that padding cannot restore missing data.

Next goal: BLOCKED until the invalid file in `ref/` is replaced with a legally owned Banjo-Kazooie NTSC-U retail dump; resume with `scripts/prepare-generated.sh <path>`.

HUMAN-VERIFY queue: none.

Blockers: BLOCKED — Phase 0 generated sources and the macOS baseline cannot proceed because the only ROM in `ref/` is an incomplete 8 MiB image. Its header claims the correct NTSC-U v1.0 revision, but a complete dump is 16 MiB and contains required data above the 8 MiB boundary. Recommendation and recovery: re-dump the full cartridge image; the result must be 16,777,216 bytes and normalize to XXH3-64 `1B67585D56E07F8C`. Renaming, byte swapping, or padding the current file cannot recover the missing data. No ROM will be searched for or downloaded.

ref/ additions: none.

Deviations from plan: 2026-07-28 — bk-decomp's pinned n64splat submodule appears worktree-dirty immediately after checkout because upstream tracks one CRLF file while declaring `text eol=lf`; the diff is line-ending-only and no source logic was changed.
