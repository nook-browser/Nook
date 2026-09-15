# Performance review — 2026-09-14

- [x] Map architecture and trace history/search/startup work.
- [x] Review tab lifecycle, resource reclamation, and background scripts.
- [x] Verify findings against callers and distinguish static evidence from measurements.
- [x] Write prioritized recommendations and a repeatable profiling plan.

Scope: review and documentation; no browser behavior changes. Runtime gains require a controlled Release-build benchmark.

Result: eight prioritized findings and profiling follow-ups in `docs/performance-review-2026-09-14.md`. Verified the startup timeout pattern with a standalone Swift reproduction (100 ms deadline, 600 ms task, 630 ms actual completion). No application build or runtime benchmark was performed.

# Implementation — 2026-09-14
- [x] Unify primary webview acquisition and release all instances on eviction; preserve multi-window/split/media behavior.
- [x] Enforce tab budgets after grace expiry and pace startup warming with power/pressure awareness.
- [x] Move history work off main, batch imports, debounce and cancel stale suggestions.
- [x] Fix startup deadline and add performance instrumentation (StartupBlockerWait, WebViewCreation, TabEviction, HistoryWrite, HistorySearch, TabPersistence signposts).
- [x] Replace full-DOM and idle polling work; gate optional shortcut/request-stat instrumentation.
- [x] Replace download polling and propagate model cancellation/unload.
- [x] Reduce redundant persistence work without weakening atomic recovery: identical snapshots skip the write; redundant post-save re-fetch removed. Dirty-record persistence still waits on profiling.
- [x] Debug and Release builds pass; `scripts/tests/history-regression.sh` passes.
- [x] Signed Release build installed to /Applications (previous copy moved to Trash).
- [ ] Manual test pass (split view, two windows, PiP, download cancel, counts toggle) and Instruments baseline. With Bain.

# Tab management review — 2026-09-15

- [x] Trace tab containers, selection, persistence, and lifecycle.
- [x] Verify suspected bugs against callers and focused reproductions.
- [x] Report prioritized findings and practical improvements.

Scope: review of the current working tree; no browser behavior changes.

Review result: seven findings in `docs/tab-management-review-2026-09-15.md`. Four extracted-Swift scenario reproductions confirmed startup merging and folder transition defects. Remaining findings were traced statically; no application build or GUI verification.

# Tab management fixes — 2026-09-15

- [x] Centralize container transfers and fix folder menu/drag/space moves.
- [x] Preserve distinct spaces, folder ordering, and per-space selection through persistence.
- [x] Validate snapshots and use complete recovery writes with explicit save outcomes.
- [x] Fix popup restoration and protect visible tabs during bulk unloading.
- [x] Add focused regressions and run builds/checks.

Result: all seven review findings fixed. Tab regression scripts pass; unsigned Debug and Release builds pass. No GUI verification yet.

# Tab management hardening — 2026-09-15 (second pass)

- [x] Parallel review: persistence/restore, webview lifecycle, structure/selection, iOS/iCloud portability.
- [x] Quit: one synchronous final snapshot in applicationShouldTerminate for every quit path; tabs are no longer closed before the save.
- [x] Persistence: snapshot builder repairs invalid folder refs instead of failing every save; rejected snapshots don't make valid ones stale; failed store load disables writes; no store deletion without a backup; CloudKit explicitly off.
- [x] Structure: Add Tab to Folder, undo close, bulk close, Clear, space/profile deletion, Move to Space, Duplicate, drag row offsets, folder close/sort/toggle persistence, sidebar Unload on the visible tab.
- [x] Lifecycle: provisional URL revert, fresh-cache restore, crash recovery, refresh fallback, popup handler isolation, adopted Peek views, timer re-arm, clone config, rename persistence, incognito leaks.
- [x] Regression scripts extended; all four pass. Debug and Release builds pass.
- [ ] Manual pass with Bain (quit and relaunch, two windows, split, folders, undo, incognito). Don't run a dev build next to the installed app: both share one store.
- [ ] Deferred: back/forward history across unload (interactionState conflicts with fresh restore), per-window restore, startup warming per new window, single-instance guard, move per-device selection out of SpaceEntity before any sync work.
