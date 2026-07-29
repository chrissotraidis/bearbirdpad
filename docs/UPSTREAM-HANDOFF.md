# Read-only upstream handoff

Status: evidence package only. BanjoPad's build loop must not create upstream branches, issues, pull requests, or pushes. The patch series in this repository remains authoritative.

## Verified upstream snapshot

Read-only `git fetch --depth=1 origin HEAD` checks on 2026-07-29 found:

| Project | Current upstream HEAD | Finding |
|---|---|---|
| N64ModernRuntime | `ae1ffbb909d9f93c88c41830deb539f7feef5ed2` | The mutable-`timestamp` `std::set` timer bug is still present. |
| plume | `d890ac899e505fb30040e037a4037cdeca68f033` | `PLUME_IOS` capability checks exist, but there is no UIKit window helper or iOS CMake source selection. |

Both current HEADs match the existing read-only reference clones. Every build and reference checkout inspected during this audit retained a fetch URL for its upstream and `DISABLED` as its push URL.

## N64ModernRuntime timer fix

The upstream-sized change is only the `ultramodern/src/timer.cpp` hunk inside [`patches/nmr/002-ios-runtime-gates-and-saves.patch`](../patches/nmr/002-ios-runtime-gates-and-saves.patch). It removes active timers by pointer identity before reinsertion or cancellation, erases the known first element without consulting a comparator whose key may already have mutated, and defensively removes stale duplicates after timer completion.

Do not include the same patch's iOS code-mod gate, save-root API, save snapshot/import API, or headers in a timer proposal. Those changes have different owners and review surfaces.

The timer-only hunk applies cleanly to current N64ModernRuntime HEAD. Before any future proposal, extract it into a focused change and add upstream-level regression coverage for:

- rearming a timer before its queued add action is consumed;
- cancelling a timer after its timestamp changes;
- repeating timers without duplicate active entries.

BanjoPad's runtime and lifecycle tests demonstrate downstream use, but they are not a substitute for those focused upstream tests.

## plume iOS work

The four plume patches are deliberately not one upstream unit:

| Patch | Handoff classification |
|---|---|
| [`001-ios-uikit.patch`](../patches/plume/001-ios-uikit.patch) | Foundation for an iOS proposal: CMake source selection, UIKit window state, and iOS-safe Metal device/presentation branches. It is proven in BanjoPad but should not be submitted alone because its asynchronous state refresh is superseded downstream. |
| [`002-guard-unavailable-metal-counter-results.patch`](../patches/plume/002-guard-unavailable-metal-counter-results.patch) | Independent, small Metal correctness fix. This is the cleanest standalone upstream candidate. |
| [`003-stabilize-uikit-window-state.patch`](../patches/plume/003-stabilize-uikit-window-state.patch) | Keep downstream. It prevents unbounded main-queue refresh work by freezing the initial full-screen geometry, but that policy is intentionally incompatible with general Stage Manager resizing. |
| [`004-ios-swapchain-availability.patch`](../patches/plume/004-ios-swapchain-availability.patch) | Keep downstream. The global C lifecycle hook matches BanjoPad's app shell; a general plume API should express availability per swapchain instead. |

All four patches replay cleanly in order on current plume HEAD. A future general-purpose UIKit proposal should start from patch `001`, replace patches `003` and `004` with an event-driven or single-flight scene-size/lifecycle API owned by the swapchain, and retain the full-screen path as a supported subset. It must also prove a physical-device present/background cycle; that remains `HUMAN-VERIFY`.

## Handoff boundary

The local handoff is complete:

1. The platform-neutral timer fix has an exact one-file extraction boundary and current-upstream replay proof.
2. The independent plume counter guard is separable now.
3. The UIKit foundation is identified, while BanjoPad-specific fixed-window and lifecycle policies remain downstream.
4. No upstream state was changed.

Actual upstream reception remains unknown by design. It is not a BanjoPad release blocker.
