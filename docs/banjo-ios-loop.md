# banjopad — Goal-Based Build Loop

You are the implementing agent for the BanjoRecomp iOS/iPadOS port. You work in `~/GitHub/banjopad`. Run this loop until the Definition of Done at the bottom is met or you hit a hard blocker. Do not wait for approval between iterations.

## Ground truth, in priority order

1. [banjo-ios-implementation-plan.md](banjo-ios-implementation-plan.md) — the plan. Phases 0-9, decisions D1-D16, touch spec, build/signing. Follow it. Where reality disagrees (upstream drift, wrong line numbers, a decision that doesn't survive contact), verify against source, do the right thing, and record the deviation in `docs/STATUS.md` and, if it changes a decision, as a dated note in the plan itself.
2. [banjo-ios-feasibility.md](banjo-ios-feasibility.md) — why the plan is what it is. Contains the verified citations and the pinned revisions table.
3. `docs/STATUS.md` — living state. You create it on iteration 1 and update it every iteration.

## The loop

Each iteration:

1. **Orient.** Read `docs/STATUS.md` (or create it), `git log --oneline -10`, and the plan section for the current phase. Determine: current phase, last completed goal, next goal.
2. **Pick one goal.** The smallest unmet acceptance criterion of the current phase (the plan's per-phase "Acceptance" lists are the goal inventory). Never work on two phases at once, except the plan's sanctioned Track A/B parallelism (Phases 2 and 3).
3. **Execute.** Implement per the plan's file-level changes. All modifications to upstream code go into `patches/<tree>/NNN-description.patch` applied over pinned `sources/` — never edit `sources/` without capturing the diff into the patch series.
4. **Verify honestly.** Run the phase's verification commands. A goal is met only when its acceptance check actually passes. Anything requiring a physical device you cannot drive: run the closest proxy (simulator, compile, static check), then mark the item `HUMAN-VERIFY` in STATUS.md with the exact steps a human must run — and continue to the next goal that isn't device-gated.
5. **Record.** Update `docs/STATUS.md`: phase, goals done this iteration (with evidence — command + result), next goal, blockers, HUMAN-VERIFY queue, ref/ additions.
6. **Commit and push** to `origin` (github.com/chrissotraidis/banjopad) — small, working increments; message describes the goal met. Run the safety checklist below before every push.
7. Repeat. If the same goal fails 3 consecutive iterations, invoke the Blocker protocol.

## The goal ladder

Exit criteria are the plan's acceptance lists — summarized here; the plan section is authoritative.

| Phase | Goal (observable) | Plan §4 |
|---|---|---|
| 0 | Pinned sources fetched; host tools built; **macOS baseline plays BK to title screen** from `sources/` | Phase 0 |
| 1 | `rt64`+plume link for arm64-iphoneos; MSL blobs built via `iphoneos` SDK; simulator configure also passes | Phase 1 |
| 2 | Metal smoke harness clears+presents on device/simulator; survives bg/fg | Phase 2 |
| 3 | Full app cross-compiles; boots headless (renderer stub) on device/sim; config appears in `Documents/`; code mods provably gated | Phase 3 |
| 4 | Launcher renders via plume-Metal; every menu navigable by touch | Phase 4 |
| 5 | ROM import via picker → hash-validated → **BK title screen with audio**, no desktop involved; `.rtz` texture pack loads | Phase 5 |
| 6 | Playable with MFi controller AND the §5 touch overlay (talon trot / eggs / wonderwing combos pass) | Phase 6 |
| 7 | Suspend/kill/relaunch matrix loses nothing; zero watchdog kills | Phase 7 |
| 8 | Perf baselines measured and recorded in `docs/perf-baseline.md`; defaults tuned | Phase 8 |
| 9 | CI green; package-audit passes; unsigned IPA + BUILDING-IOS.md; tag `v0.1.0` | Phase 9 |
| 10+ | Polish backlog: curated texture-pack recommendations (from `ref/`), iPhone scale tuning, DD1/DD3/DD5 items, pin-bump to current upstream | Plan §2 DDs |

## ref/ — the reference folder

`ref/` is local-only working material. Everything in it except `README.md` is gitignored and must stay that way.

- **The original game ROM lives in `ref/`.** The user places their retail Banjo-Kazooie NTSC-U dump there (`.z64`/`.v64`/`.n64`, any byte order). On Phase 0 you: locate it, normalize byte order if needed, verify it (retail runtime hash XXH3-64 `0x1B67585D56E07F8C`; decompressed build input sha1 `1fb13cad402518d3ae9a8dc4b52c5c54b2a4adc7` after running `bk_rom_compressor` from the bk-decomp tools), and stage the decompressed copy into `sources/banjo/` for the recompilers. If no ROM is present in `ref/`, record `BLOCKED: ROM missing from ref/` in STATUS.md and stop — do not search elsewhere for one and never download one.
- **Clone whatever GitHub projects genuinely help, into `ref/`,** and log each in `ref/README.md` (URL, commit, one-line purpose). Baseline set to fetch on iteration 1:
  - `AurelioB/BanjoRecomp-Android` — the structural map; its `docs/plans/` and its forks of nmr/rt64/frontend are the source for the D13/D14 cherry-picks and the null-NFD / `NullRendererContext` patches.
  - `chrissotraidis/harkinianpad` (or the local `~/GitHub/harkinianpad` checkout) — iOS shell, packaging-audit, INSTALL_IPA, and touch-control templates.
  - `N64Recomp/N64Recomp`, `N64Recomp/N64ModernRuntime`, `rt64/rt64` at current HEAD — read-only, for checking whether upstream has moved on anything we patch (timer fix, plume iOS) before writing it ourselves.
  - Community enhancement material as it becomes relevant (Phase 5+/10): Banjo-Kazooie HD texture packs and `.rtz` releases, BanjoRecomp mod repos (for testing the data-only path and writing the recommended-packs doc), `Zelda64Recomp/Zelda64Recomp` (for cross-checking runtime usage patterns). Judge each by: does it help a phase goal or the polish backlog. Record why in `ref/README.md`.
- ref/ is for *reference and test inputs*. Build inputs are the pinned checkouts in `sources/` created by `scripts/fetch-sources.sh` — never build the app from ref/ clones.

## Hard rules

1. **The ROM never leaves the machine.** Never committed, never pushed, never uploaded, never copied outside the repo working tree, path may appear in logs but contents never. Same for everything ROM-derived (`RecompiledFuncs/`, `RecompiledPatches/`, `rsp/n_aspMain.cpp`, decompressed variants). The `.gitignore` enforces this; treat a gitignore edit that weakens it as forbidden.
2. **Push only to `chrissotraidis/banjopad`.** Every upstream repo is read-only: no pushes, no branches, no PRs, no issues. `fetch-sources.sh` sets push URLs to `DISABLED`; keep it that way.
3. **Before every push:** `git status` shows no ROM-pattern files staged; `git ls-files | grep -E '\.z64|\.v64|\.n64|RecompiledFuncs|RecompiledPatches|n_aspMain'` is empty; nothing under `ref/` except `README.md` is tracked.
4. **The macOS baseline stays green.** After any patch touching shared code, rebuild the Phase 0 macOS target before counting the goal met. Desktop behavior is the regression canary (plan §9).
5. **No fabricated verification.** If a check didn't run or didn't pass, the goal is open. HUMAN-VERIFY items stay in the queue until a human confirms; never silently self-approve them.
6. **Pin discipline.** Work happens on the pinned revisions in the feasibility table. Bump pins only as a deliberate, single-purpose iteration (plan R2 procedure), never mid-phase.
7. Estimates you write down are labeled estimates. Unknowns are written as `unknown`, not filled in.

## docs/STATUS.md format

```
# Status — updated <date, iteration N>
Phase: <n> — <name>          Track A/B state if split
Done this iteration: <goal> — evidence: <command → result>
Next goal: <single goal>
HUMAN-VERIFY queue: <item — exact steps for the human>
Blockers: <none | list>
ref/ additions: <repo @ commit — purpose>
Deviations from plan: <none | dated list>
```

## Blocker protocol

On 3 consecutive failures of one goal, or a structural surprise (e.g. plume-Metal broken beyond the plan's gap list — the plan's Phase 2 decision gate):

1. Write a `BLOCKED` entry in STATUS.md: what failed, evidence, what was tried, the decision it forces (with your recommendation and the plan's fallback if one exists — e.g. D2's MoltenVK note).
2. Commit and push the state so nothing is lost.
3. Move to the next non-dependent goal if one exists; otherwise stop the loop and surface the blocker as your final report.

## Definition of Done

Phases 0-9 complete: `v0.1.0` tagged on `chrissotraidis/banjopad`; CI green including package-audit; an unsigned IPA a user can sideload; the HUMAN-VERIFY queue contains only device-gated confirmations with exact reproduction steps; STATUS.md's final entry says so. Then work the Phase 10+ polish backlog until stopped.
