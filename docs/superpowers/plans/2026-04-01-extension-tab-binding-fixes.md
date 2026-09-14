# Extension Tab Binding Fixes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix Bitwarden (and other Safari `.appex` extensions) so they know the active tab, autofill works, and the popup doesn't needlessly reload.

**Architecture:** Five surgical fixes to existing extension lifecycle code — no new files, no architecture changes. Fixes: (A) grant URL access on tab activation, (B) guard tab notifications against nil webviews, (C) eliminate popup double-load, (D) fire URL/title property changes on tab switch, (E) remove redundant background-wake in delegate.

**Tech Stack:** Swift 5, WKWebExtension (macOS 15.4+/15.5+), WKWebExtensionController

---

## File Map

| File | Changes |
|------|---------|
| `Nook/Managers/ExtensionManager/ExtensionManager+TabNotifications.swift` | Tasks 1, 4 — grant URL on activation, fire property changes |
| `Nook/Managers/TabManager/TabManager.swift:2510-2518` | Task 2 — guard `notifyTabOpened` against nil webviews |
| `Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:46-59,91-97` | Tasks 3, 5 — remove popup double-load and redundant background-wake |

---

### Task 1: Grant URL access and fire property changes on tab activation

When extensions call `chrome.tabs.query({active: true, currentWindow: true})` after a tab switch, WebKit asks our adapter for the active tab. The URL is available (via `tab.url`), but WebKit's permission model requires **explicit** URL grants per-context — without them, content scripts can't inject and the popup can't read the tab's URL. Currently `grantExtensionAccessToURL` only fires during `decidePolicyFor navigationAction` and `loadURL`, not on tab activation.

Additionally, when a tab becomes active, the background worker doesn't receive `.URL`/`.title` property change notifications, so it doesn't re-evaluate autofill state for the page.

**Files:**
- Modify: `Nook/Managers/ExtensionManager/ExtensionManager+TabNotifications.swift:62-75`

- [ ] **Step 1: Add URL grant and property notifications to `notifyTabActivated`**

After the existing `wakeBackgroundWorkers()` call at the end of `notifyTabActivated`, add URL grant and property change notifications:

```swift
@available(macOS 15.4, *)
func notifyTabActivated(newTab: Tab, previous: Tab?) {
    guard let bm = browserManagerRef, let controller = extensionController
    else { return }
    let newA = adapter(for: newTab, browserManager: bm)
    let oldA = previous.map { adapter(for: $0, browserManager: bm) }
    controller.didActivateTab(newA, previousActiveTab: oldA)
    controller.didSelectTabs([newA])
    if let oldA { controller.didDeselectTabs([oldA]) }
    tabCacheGeneration &+= 1

    // Wake MV3 background workers on tab switch so they can update
    // badge counts and autofill state for the newly active tab.
    wakeBackgroundWorkers()

    // Grant all extension contexts explicit access to the active tab's URL.
    // Without this, content scripts can't inject and chrome.tabs.query()
    // won't return the URL — WebKit requires per-URL grants even when
    // match patterns already cover the domain.
    if let url = newTab.url.scheme.flatMap({ ["http", "https"].contains($0) ? newTab.url : nil }) {
        grantExtensionAccessToURL(url)
    }

    // Fire property changes so background workers re-evaluate the page
    // (autofill detection, badge text, declarativeContent rules).
    controller.didChangeTabProperties([.url, .title], for: newA)
    tabCacheGeneration &+= 1
}
```

Note: The `url` guard filters to http/https only — extension access grants for `about:blank`, `nook://`, etc. are meaningless and would pollute the permission table.

- [ ] **Step 2: Build and verify**

Run:
```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Manual test**

1. Launch Nook, open two tabs (e.g. `github.com` and `bitwarden.com`)
2. Switch between them
3. Click Bitwarden extension icon — popup should show credentials matching the **active** tab's URL
4. Switch to the other tab, click Bitwarden again — should show credentials for the new URL

---

### Task 2: Guard `notifyTabOpened` against nil webviews in TabManager

`TabManager.reattachBrowserManager()` (line 2510-2518) calls `notifyTabOpened` for ALL tabs during startup, including tabs whose webviews haven't been lazily created yet. `ExtensionManager.attach()` correctly filters `!tab.isUnloaded`, but this path doesn't. Tabs with nil webviews cause WebKit to cache stale state — content script messages can't match to tab adapters because `ExtensionTabAdapter.webView(for:)` returns nil.

**Files:**
- Modify: `Nook/Managers/TabManager/TabManager.swift:2509-2518`

- [ ] **Step 1: Add webview guard to tab notification loop**

Change the extension notification block to only notify about tabs that have webviews:

```swift
// Inform the extension controller about existing tabs and the active tab
if #available(macOS 15.5, *) {
    for t in allTabs() where t.didNotifyOpenToExtensions == false && !t.isUnloaded {
        ExtensionManager.shared.notifyTabOpened(t)
        t.didNotifyOpenToExtensions = true
    }
    if let current = self.currentTab, !current.isUnloaded {
        ExtensionManager.shared.notifyTabActivated(newTab: current, previous: nil)
    }
}
```

The key change: `&& !t.isUnloaded` on line 2511 and `!current.isUnloaded` on line 2515. Tabs without webviews will self-register via `notifyTabOpened()` later when their webview is lazily created in `Tab.setupWebView()` (line 631).

- [ ] **Step 2: Build and verify**

Run:
```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

---

### Task 3: Remove popup double-load

`presentActionPopup` (line 95-96) explicitly calls `webView.load(URLRequest(url: popupURL))` every time the popup opens. The comment says WebKit creates the webview "with a URL set but not always loading." However, this forces a **full** reload of the popup HTML/JS even when WebKit already kicked off the load. For Bitwarden's complex popup UI, this adds visible latency.

The fix: only trigger the load if the webview has no content AND isn't loading. If WebKit already started loading, don't interfere.

**Files:**
- Modify: `Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:91-97`

- [ ] **Step 1: Conditionally load popup only when WebKit hasn't started**

Replace the unconditional load block:

```swift
// Old (lines 91-97):
Self.logger.debug("Popup webView: URL=\(webView.url?.absoluteString ?? "nil", privacy: .public), isLoading=\(webView.isLoading)")
if !webView.isLoading, let popupURL = webView.url {
    webView.load(URLRequest(url: popupURL))
}
```

With a smarter check:

```swift
Self.logger.debug("Popup webView: URL=\(webView.url?.absoluteString ?? "nil", privacy: .public), isLoading=\(webView.isLoading), hasContent=\(webView.estimatedProgress > 0)")

// Only trigger a load if WebKit hasn't started loading the popup yet.
// WebKit creates the popup webview with a URL but sometimes doesn't start
// the load. If it already started (isLoading or has progress), don't
// force a full reload — that causes visible flicker for complex popups.
if !webView.isLoading, webView.estimatedProgress == 0, let popupURL = webView.url {
    webView.load(URLRequest(url: popupURL))
}
```

- [ ] **Step 2: Build and verify**

Run:
```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Manual test**

1. Open Nook, navigate to a login page
2. Click Bitwarden icon — observe the popup appearance
3. Close the popup, click again immediately — should appear noticeably faster than before
4. If the popup shows blank content, the `estimatedProgress` check may be too aggressive — revert to the old check in that case

---

### Task 4: Remove redundant background-wake in popup delegate

`ExtensionActionView.showExtensionPopup()` already awaits `loadBackgroundContent()` before calling `performAction()`. The delegate's `presentActionPopup` then fires ANOTHER background wake (lines 50-58), but without awaiting — it's fire-and-forget inside a detached Task. This double-wake is wasteful and the un-awaited one can race with the popup load.

**Files:**
- Modify: `Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:46-59`

- [ ] **Step 1: Remove the redundant background-wake from the delegate**

Replace the background-wake block in `presentActionPopup`:

```swift
// Old (lines 46-59):
// Ensure background service worker is alive before showing the popup.
// MV3 workers auto-terminate after ~5 min of inactivity; if the popup
// tries chrome.runtime.sendMessage and the worker is dead, it hangs forever.
if extensionContext.webExtension.hasBackgroundContent {
    Task { @MainActor in
        do {
            try await extensionContext.loadBackgroundContent()
            Self.logger.debug("Background worker alive for '\(extName, privacy: .public)'")
        } catch {
            Self.logger.error("Failed to wake background worker for '\(extName, privacy: .public)': \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

With a comment explaining why it's not needed:

```swift
// Background worker is already awaited by ExtensionActionView.showExtensionPopup()
// before performAction() is called. No need to double-wake here.
```

- [ ] **Step 2: Build and verify**

Run:
```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

---

### Task 5: Verify and commit all changes

- [ ] **Step 1: Full build**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | tail -5
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 2: Manual integration test**

Test matrix with Bitwarden Safari extension:

| Test | Expected |
|------|----------|
| Open login page, check for autofill icons in fields | Bitwarden icons appear in username/password fields |
| Click extension icon on login page | Popup shows credentials matching the page URL |
| Switch tabs to different login page, click extension | Popup shows credentials for NEW page |
| Close popup, reopen immediately | Popup appears quickly without full reload flicker |
| Open Nook fresh with multiple tabs, click extension | Popup shows correct active tab's credentials |
| Navigate to new page on same tab, click extension | Popup shows credentials for new URL |

- [ ] **Step 3: Commit**

```bash
git add Nook/Managers/ExtensionManager/ExtensionManager+TabNotifications.swift \
       Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift \
       Nook/Managers/TabManager/TabManager.swift
git commit -m "fix(extensions): improve tab binding for Bitwarden and Safari extensions

- Grant URL access to all extension contexts on tab activation so
  chrome.tabs.query() returns the active tab's URL
- Fire .url/.title property changes on tab switch so background workers
  re-evaluate autofill state
- Skip notifyTabOpened for tabs without webviews during startup to
  prevent stale state in WKWebExtensionController
- Only reload popup webview when WebKit hasn't started loading it,
  reducing popup open latency
- Remove redundant background-wake in presentActionPopup delegate
  (already awaited by ExtensionActionView)"
```
