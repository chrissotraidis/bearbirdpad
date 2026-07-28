# Status — updated 2026-07-28, iteration 3

Phase: 0 — Pinned sources, host tools, macOS baseline

Done this iteration: ROM validation and idempotent generated-source preparation tooling implemented; the generated-source goal remains open — evidence: `./scripts/build-host-tools.sh` → native arm64 `rom_xxh3` built against the pinned runtime's xxHash; `./scripts/prepare-generated.sh 'ref/Banjo-Kazooie (U) [!].z64'` → rejected before decompression with expected XXH3-64 `1B67585D56E07F8C`, found `D287BE61F6682734` (failure 1/3); source check → the pinned compressor accepts NTSC-U MD5 `b29599651a13f681c9923d69354bf4a3`, while this already-big-endian 8 MiB file is `4bc8449426ca1c72b7b0bb1323dad47f`.

Next goal: replace the invalid file in `ref/` with a legally owned Banjo-Kazooie NTSC-U retail dump and rerun `scripts/prepare-generated.sh <path>`.

HUMAN-VERIFY queue: none.

Blockers: BLOCKED — the only ROM in `ref/` is not the required NTSC-U retail image. A valid dump must normalize to runtime XXH3-64 `1B67585D56E07F8C`; no ROM will be searched for or downloaded.

ref/ additions: none.

Deviations from plan: 2026-07-28 — bk-decomp's pinned n64splat submodule appears worktree-dirty immediately after checkout because upstream tracks one CRLF file while declaring `text eol=lf`; the diff is line-ending-only and no source logic was changed.
