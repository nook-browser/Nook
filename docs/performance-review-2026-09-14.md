# Nook performance review

Reviewed commit `88bbeee`, September 14, 2026. Scope: source review of webview ownership, tab reclamation, startup, history/search, injected scripts, downloads, persistence, and local inference. No application behavior was changed.

## Assessment

The highest-value improvements are reliable webview reclamation, eliminating duplicate page creation, and removing repeated main-thread/database and page-script work. These preserve browser features while reducing their ongoing cost. Existing strengths include lazy tab restoration, memory-pressure handling, debounced persistence on a separate actor, cached content-blocker compilation, and on-demand local model loading.

These are code-backed findings, not measured application speedups. Nook was not running during review; unrelated WebKit processes cannot establish its footprint. No full application benchmark or build was run for this documentation-only review.

## Prioritized findings

### 1. High: tab unloading leaves coordinator-owned webviews alive

Evidence: `TabManager.swift:1469`, `TabCompositorView.swift:101`, `Tab.swift:1246–1353`, `WebViewCoordinator.swift:16,94,206`.

Normal timeout/pressure unloading calls `Tab.unloadWebView()`, which strips handlers/delegates and clears `_webView`. The coordinator's dictionary still strongly retains the primary and any window clones. Closing a tab separately removes coordinator views, but ordinary unloading does not. The coordinator can subsequently return the stripped cached view. Clearing the tab reference therefore does not establish that the page was released; cookie-store reads in teardown do not establish process termination either.

Recommendation: centralize acquisition and eviction under one owner. Evict all nonvisible instances, detach observers/handlers, release compositor and coordinator references, and retain only restoration metadata. Reacquisition must create or fully reinitialize a valid view. Verify with weak-reference/deallocation checks and a memory graph, then measure WebContent footprint after a settling period; WebKit may retain shared processes/caches after view release.

### 2. High: first selection can create and load two webviews

Evidence: `BrowserManager.swift:1982` → `TabCompositorView.swift:109` → `Tab.swift:1374,518,618`; `WebViewCoordinator.swift:94–108,146–185`.

Selecting an unloaded tab first creates/loads its own webview. A coordinator cache miss then creates and loads another view, copying only the existing configuration before replacing the primary reference. Startup's coordinator-preload path avoids this particular sequence; ordinary first selection still exposes it. This schedules redundant page initialization/navigation, even if cancellation or caching reduces actual network transfers.

Recommendation: have the coordinator adopt a valid existing primary, or make it the sole construction path. Clone only for simultaneous presentation in another window. Count creations and navigations for new, restored, and previously unloaded tabs.

### 3. High: history work scales with database size on the main actor

Evidence: `HistoryManager.swift:12,35–85,138–156`; `SearchManager.swift:74–92`; `CommandPaletteView.swift:195–204`; `BrowserManager.swift:2353–2364`.

Every visit fetches all history entities, filters by URL in memory, and saves synchronously. Address-bar edits immediately fetch/filter up to 5,000 entries, despite displaying only a few matches. History import repeats the full-table lookup/save for each entry, approaching quadratic work as the store grows.

Recommendation: query exact URL candidates in the store, preserve profile/nil-profile matching semantics, and add appropriate indexes after validating schema migration. Move history operations to a dedicated model actor, returning value records to the UI. Batch imports. Keep tab matches immediate; debounce history/network suggestions (start by evaluating 100–150 ms) and reject stale results. Preserve search semantics when replacing localized string matching; a simple index does not automatically accelerate arbitrary substring search.

Validation: navigation and typing with 1k/10k/50k history entries; report main-thread time, query duration, keystroke-to-result latency, and import throughput.

### 4. High: startup's advertised two-second timeout is ineffective

Evidence: `BrowserManager.swift:609–623`.

The task group races blocker activation against a sleep, then cancels the group. The child awaiting the independent activation task still waits for its result; group exit waits for all children. Slow activation can therefore delay the initial page beyond two seconds.

Verified with a standalone reproduction using the installed Swift 6.3.3 toolchain: a 100 ms timeout around 600 ms activation returned in **630 ms**. This validates the concurrency pattern, not Nook's actual startup duration. [Apple documents that task groups await children and cancellation is cooperative](https://developer.apple.com/documentation/Swift/TaskGroup).

Recommendation: use a cancellation-aware waiter or separately owned completion/deadline tasks with a single-resume gate. Preserve blocker activation and explicitly define whether the deadline shows a loading state or permits navigation before blocking is ready.

### 5. Medium: injected scripts repeatedly scan entire documents

Evidence: `Tab.swift:1977–2021,1099,1233,2572`; `WebsiteShortcutDetector.swift:255–281`.

Link-hover support queries all links and attaches per-link listeners; every relevant mutation batch schedules another full scan without coalescing pending scans. Shortcut detection similarly scans all access keys on subtree changes and is injected unconditionally. Media detection polls each live page every five seconds and posts state even when unchanged, with additional site-specific mutation checks.

Recommendation: delegate link hover at the document level; process changed access-key nodes, coalesce mutation work, and gate shortcut instrumentation on feature enablement. Favor media events/native state, deduplicate bridge messages, and limit fallback polling to pages that need it. Preserve background playback detection; do not blindly disable media tracking on hidden tabs.

Validation: a mutation-heavy feed and a static page, with 1/20/50 loaded tabs. Compare JavaScript CPU, bridge messages, wakeups, scrolling, and idle energy.

### 6. Medium: cancelled downloads can leave permanent polling workers

Evidence: `DownloadManager.swift:307–310,524,554–597`.

Each monitored download occupies a background worker that stats the destination every 500 ms. The exit condition accepts only completed/failed, although cancellation explicitly sets cancelled. The closure retains the delegate and download; removing the dictionary entry does not stop it. State is also read from the worker while changed on the main actor.

Recommendation: observe supported [WKDownload progress](https://developer.apple.com/documentation/webkit/wkdownload) and explicitly tear down observation on every terminal state/removal. If a fallback is necessary, use an owned cancellable mechanism rather than a sleeping thread. Verify cancellation and clearing downloads leave no continuing file reads.

### 7. Medium: correct eviction eligibility before making it more aggressive

Evidence: `TabCompositorView.swift:155–166,280–305`; `SplitViewManager.swift:29–37`.

Visibility protection checks only each window's current tab, omitting the other visible split pane. The loaded-tab cap also excludes tabs accessed within 30 seconds, without scheduling a cap recheck when that grace period expires. Burst opening can exceed the intended cap until another enforcement trigger or ordinary unload timeout.

Recommendation: maintain a shared set of visible/protected tab IDs including both split panes and relevant media/capture states. Schedule a one-shot enforcement pass for the earliest grace expiry. Fix ownership in finding 1 first; otherwise a stricter policy may strip visible pages without reclaiming them.

### 8. Medium: local inference unloading does not cancel active work

Evidence: `LocalLLMEngine.swift:120–132,174–205,219–228,259–261`.

Loading and generation use detached tasks whose handles are not retained. Critical memory pressure clears `modelContainer`, but active generation retains its own container; an in-flight load can repopulate the property afterward. Caller cancellation has no explicit propagation to these tasks.

Recommendation: retain task handles, propagate cancellation through the inference stream, reject obsolete load completions, and serialize lifecycle transitions. Verify actual model/GPU allocation release after cancellation and pressure; setting a property to nil alone is insufficient evidence.

## Follow-up opportunities to profile

- Startup defaults to favorites plus the current space (`NookSettingsService.swift:385–387`; `BrowserManager.swift:650–669`). Prefer active-tab-first with bounded, low-priority warming of likely next tabs. Keep broad preloading as a user choice and account for low power/memory pressure.
- Request statistics maintain another matching engine and instrument page requests (`RequestStatsEngine.swift:76–84`, `ContentBlockerManager.swift:176–178`). Benchmark counts enabled/disabled separately from actual ad blocking before deciding whether to make detailed statistics opt-in or lazy.
- Persistence is already debounced/off-main, but each snapshot reconciles all tabs/folders/spaces and validates twice (`TabManager.swift:158–231`). Profile large sessions before introducing dirty-record persistence; retain atomicity and recovery behavior.

## Implementation order and verification

1. Establish a Release-build baseline; add signposted intervals for startup, tab acquisition/display, history query/save, blocker activation, and persistence. No signpost instrumentation was found in app Swift sources.
2. Fix webview ownership and duplicate creation together; include split-view and multi-window lifecycle regression coverage.
3. Fix history/search and startup waiting; then remove download and DOM background work.
4. Tune warming, eviction budgets, inference lifecycle, and optional statistics using measured results.

Use an isolated disposable profile with a fixed site set and extension configuration. Compare five or more runs under the same power/thermal conditions, separating cold and warm startup. Test 1/20/50 tabs, two windows, split view, audio/PiP, close/reopen, download cancellation, large history, and local-model use. Record median/p95 startup and tab-switch latency, main-thread stalls, idle CPU/wakeups, and Nook plus its attributed WebContent/GPU/network memory. Include a ten-minute idle period and a repeat open/unload cycle to distinguish transient caches from monotonically retained state. Treat lower footprint and unchanged functional behavior as acceptance criteria; do not claim a percentage improvement before measuring it.
