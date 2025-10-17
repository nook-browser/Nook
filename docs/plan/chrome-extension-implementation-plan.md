# Chrome Extension Implementation Plan

## Overview

This document outlines the implementation plan to make Chrome extensions fully operational in Nook browser. The plan is based on a deep review of the `feat/fix-extension-popup-loading` branch and uses Dark Reader as the reference extension for validation.

## Current State Summary

### What's Working
- ✅ Action popup (MV3) loads and is positioned correctly
- ✅ Storage (local) works and persists
- ✅ Tabs API for basic flows (query/create/update/remove)
- ✅ Scripting API basics (executeScript/insertCSS/removeCSS)
- ✅ Permissions and host access auto-granting
- ⚠️ Commands (keyboard) - partial (parsing works, event delivery blocked)
- ⚠️ Context menus - partial (create/update works, click routing blocked)

### Critical Gaps
1. **Background/service worker message delivery** - `getBackgroundWebView()` returns nil
2. **Runtime messaging completeness** - synthetic responses instead of real service worker communication
3. **Content script injection semantics** - manual injection instead of native WebKit handling
4. **Frame targeting** - missing iframe support in scripting API
5. **chrome.storage.sync** - not implemented (falls back needed)
6. **Commands/contextMenus event routing** - blocked by missing background dispatch

## Typical Extension Requirements

Most Chrome extensions (including Dark Reader as a reference) rely on:
- `chrome.runtime` (messaging, getManifest, connect)
- `chrome.storage` (local, sometimes sync)
- `chrome.tabs` (query, sendMessage)
- `chrome.action` (popup)
- `content_scripts` on various match patterns with `all_frames` support
- Bidirectional messaging (popup ↔ background, content ↔ background)
- CSS/JS injection across frames
- Optional: `chrome.commands` (hotkeys) and `chrome.contextMenus`

Not all extensions require:
- `webRequest` or `declarativeNetRequest`

## Implementation Phases

---

## Phase 1: Background/Service Worker Foundation (P0 - Blockers)

### Task 1.1: Implement WKWebExtension.MessagePort Management

**Goal**: Replace the nil-returning `getBackgroundWebView` with proper MessagePort-based communication

**What to build**:
- Store and manage MessagePort instances per extension in ExtensionManager
- Implement `webExtensionController(_:connectUsing:for:completionHandler:)` delegate to capture ports when extensions call `runtime.connect()`
- Create a port registry keyed by extension ID and port name
- Add lifecycle management (port creation, disconnection, cleanup)

**Files to modify**:
- `Nook/Managers/ExtensionManager/ExtensionManager.swift`
  - Add port storage dictionary: `private var extensionMessagePorts: [String: WKWebExtension.MessagePort] = [:]`
  - Add management methods:
    - `func registerMessagePort(_ port: WKWebExtension.MessagePort, for extensionId: String, name: String)`
    - `func getMessagePort(for extensionId: String, name: String?) -> WKWebExtension.MessagePort?`
    - `func removeMessagePort(for extensionId: String, name: String)`
    - `func disconnectAllPorts(for extensionId: String)`
  - Flesh out the delegate method at line ~4040 (currently just calls `completionHandler(nil)`)

**Acceptance criteria**:
- Extension can establish a port via `runtime.connect()`
- Manager maintains reference to active ports
- Ports are cleaned up on disconnection

**Estimated effort**: 1-2 days

---

### Task 1.2: Route runtime.sendMessage to Service Worker via Native Path

**Goal**: Make popup→background and content→background messaging work through real service worker

**What to build**:
- In `ExtensionManager+Runtime.swift`, modify `handleRuntimeMessage` to:
  - Detect if target is the background context
  - Use WKWebExtensionContext's native message delivery APIs
  - Wait for actual response from service worker
  - Remove synthetic `"success": true` responses
- Implement proper error handling for message delivery failures
- Add logging to track message round-trips
- This enables proper communication for all extensions, not just specific ones

**Files to modify**:
- `Nook/Managers/ExtensionManager/ExtensionManager+Runtime.swift`
  - `handleRuntimeMessage` method
  - `deliverMessageToContext` method

**Technical approach**:
```swift
// Instead of synthetic response:
// replyHandler(["success": true], nil)

// Use native delivery:
extensionContext.sendMessage(message, toApplicationWithIdentifier: extensionId) { response, error in
    if let error = error {
        replyHandler(nil, error)
    } else {
        replyHandler(response, nil)
    }
}
```

**Acceptance criteria**:
- `chrome.runtime.sendMessage()` from popup reaches service worker
- Service worker response flows back to caller
- No synthetic success messages masking failures
- Console logs show real round-trip communication

**Estimated effort**: 2-3 days

---

### Task 1.3: Implement Port-Based Event Delivery for Commands/ContextMenus

**Goal**: Replace `_trigger` eval attempts with MessagePort delivery

**What to build**:
- In `ExtensionManager+Commands.swift`:
  - Replace `getBackgroundWebView()` call with MessagePort lookup
  - Format command events as structured messages matching `chrome.commands.onCommand` event structure
  - Send through MessagePort to service worker
- In `ExtensionManager+ContextMenus.swift`:
  - Do the same for menu clicks
  - Format as `chrome.contextMenus.onClicked` events

**Files to modify**:
- `Nook/Managers/ExtensionManager/ExtensionManager+Commands.swift`
  - Command trigger path (where NSEvent monitor fires)
- `Nook/Managers/ExtensionManager/ExtensionManager+ContextMenus.swift`
  - Menu click handler

**Event format examples**:
```javascript
// chrome.commands.onCommand
{
  type: "command",
  command: "toggle-dark-mode"
}

// chrome.contextMenus.onClicked
{
  type: "contextMenuClick",
  menuItemId: "toggle-site",
  pageUrl: "https://example.com",
  frameUrl: "https://example.com"
}
```

**Acceptance criteria**:
- Keyboard shortcut triggers `chrome.commands.onCommand` in service worker
- Context menu click triggers `chrome.contextMenus.onClicked` in service worker
- Events include correct data structure

**Estimated effort**: 1-2 days

---

## Phase 2: Content Script Native Injection (P0 - Blockers)

### Task 2.1: Audit and Verify WebView Controller Attachment

**Goal**: Ensure all browsing WebViews have `.webExtensionController` set before navigation

**What to verify**:
- Check `BrowserConfig.swift` and Tab initialization code
- Confirm controller is set immediately on WebView creation, before any `loadRequest`
- Add logging to track controller attachment timing
- Verify no race conditions between controller attachment and page load

**Files to check**:
- `Nook/BrowserConfig.swift`
- Tab creation/initialization code
- Any WebView factory methods
- `Nook/Models/Tab.swift`

**What to look for**:
```swift
// Ensure this happens immediately after WebView creation:
webView.webExtensionController = ExtensionManager.shared.getController()
```

**Acceptance criteria**:
- All page-load WebViews have controller attached before navigation
- Native content_scripts injection fires automatically
- Logging confirms timing is correct

**Estimated effort**: 1 day

---

### Task 2.2: Reduce/Eliminate Manual Content Script Injection

**Goal**: Let WKWebExtension handle content_scripts from manifest natively

**What to do**:
- Review `ExtensionManager+Scripting.swift` manual injection logic
- Determine if manual injection is still needed after controller attachment is verified
- Keep manual injection only for:
  - Dynamic `chrome.scripting.executeScript()` calls (not manifest-declared scripts)
  - Fallback scenarios
- Remove duplicate injection (both native and manual firing)
- Add feature flag to control manual vs. native injection for testing

**Files to modify**:
- `Nook/Managers/ExtensionManager/ExtensionManager+Scripting.swift`
  - Manifest content_scripts injection logic
  - Consider gating with `if !useNativeInjection { ... }`
- Manifest parsing code if needed

**Acceptance criteria**:
- Dark Reader content scripts appear in pages via native injection
- No duplicate script execution observed
- Console logs confirm scripts are injected by WebKit, not manually

**Estimated effort**: 1-2 days

---

### Task 2.3: Verify run_at, all_frames, and world Semantics

**Goal**: Confirm timing and frame targeting match Dark Reader's manifest expectations

**What to test**:
- Load extensions on pages with complex iframe structures:
  - YouTube (video embeds, ads)
  - Google Docs (editor iframes)
  - News sites with embedded content
- Check browser console and WebKit logs for injection timing
- Verify `all_frames: true` injects into all subframes
- Confirm world isolation (ISOLATED vs MAIN)

**Files to check**:
- Native WKWebExtension behavior (mostly WebKit-side)
- Any custom injection or timing override in Scripting manager
- Dark Reader manifest.json to understand expected behavior

**Test cases**:
1. Script with `"run_at": "document_start"` runs before DOM loads
2. Script with `"run_at": "document_end"` runs after DOM ready but before images/resources
3. Script with `"run_at": "document_idle"` runs after page fully loaded
4. `"all_frames": true` injects into main frame and all iframes
5. Scripts run in isolated world by default (MV3)

**Acceptance criteria**:
- Scripts run at correct timing (document_start/end/idle)
- All iframes receive content scripts when `all_frames: true`
- World isolation works as expected
- No timing races or flickering observed

**Estimated effort**: 1 day (mostly testing)

---

## Phase 3: High Priority Enhancements (P1)

### Task 3.1: Implement Frame Targeting in chrome.scripting

**Goal**: Support `frameIds` parameter in executeScript/insertCSS/removeCSS

**What to build**:
- Extend scripting API to parse `frameIds` from API calls
- Map frameIds to WKFrameInfo instances in target WebView
- Execute script/CSS in specified frames instead of always main frame
- Handle `"allFrames": true` flag properly
- Handle `frameId: 0` (main frame) explicitly

**Files to modify**:
- `Nook/Managers/ExtensionManager/ExtensionManager+Scripting.swift`
  - `executeScript` method
  - `insertCSS` method
  - `removeCSS` method

**API format**:
```javascript
chrome.scripting.executeScript({
  target: { 
    tabId: 123, 
    frameIds: [0, 5, 7],  // Support this
    allFrames: false       // Or this
  },
  func: () => { /* ... */ }
})
```

**Technical approach**:
- Get WebView for tab
- If `frameIds` specified, iterate and execute in each frame
- If `allFrames: true`, execute in main frame and all child frames
- Map frame IDs to WKFrameInfo using WebView's frame hierarchy

**Acceptance criteria**:
- Extensions can inject styles/scripts into specific iframes
- `frameIds` parameter works correctly
- `allFrames` parameter works correctly
- Main frame (frameId 0) can be targeted explicitly

**Estimated effort**: 2 days

---

### Task 3.2: Implement chrome.storage.sync Shim

**Goal**: Prevent errors when extensions read/write sync storage

**What to build**:
- Add "sync" storage area to ExtensionStorageManager
- Alias sync to local storage for now
- Return same data but mark as sync storage for API compliance
- Add TODO comment noting this is not true cloud sync

**Files to modify**:
- `Nook/Managers/ExtensionManager/ExtensionStorageManager.swift`
  - Add sync storage handling (map to local)
- `Nook/Managers/ExtensionManager/ExtensionManager+Storage.swift`
  - Update bridge to support sync area

**Implementation**:
```swift
// In ExtensionStorageManager
func getSync(keys: [String], for extensionId: String) -> [String: Any] {
    // For now, sync is just an alias to local
    return getLocal(keys: keys, for: extensionId)
}

func setSync(items: [String: Any], for extensionId: String) {
    // For now, sync is just an alias to local
    setLocal(items: items, for: extensionId)
}
```

**Acceptance criteria**:
- `chrome.storage.sync.get()` works without errors
- `chrome.storage.sync.set()` works without errors
- Data persists locally (same as storage.local)
- onChanged events fire for sync area

**Estimated effort**: 0.5-1 day

---

### Task 3.3: Route Commands and ContextMenus to Service Worker

**Goal**: Complete the event routing started in Phase 1, ensuring end-to-end flow

**What to verify**:
- Commands registered from manifest appear in system
- Command key bindings trigger events correctly
- Context menu items created from background show in Nook UI
- Menu clicks route back to service worker
- Event data structure matches Chrome's format exactly

**Files to modify**:
- `Nook/Managers/ExtensionManager/ExtensionManager+Commands.swift`
  - Verify event payload format matches Chrome
- `Nook/Managers/ExtensionManager/ExtensionManager+ContextMenus.swift`
  - Verify click event payload matches Chrome

**Testing**:
- Configure a command in extension manifest
- Verify command appears in Nook's UI (if applicable)
- Press the hotkey and observe service worker console
- Create context menu item from background
- Right-click and verify menu appears
- Click menu and observe service worker console

**Acceptance criteria**:
- Hotkey triggers expected extension behavior
- Context menu click triggers expected extension action
- Events reach service worker with correct data structure
- No errors in console

**Estimated effort**: 1 day

---

## Phase 4: Hardening and Polish (P2)

### Task 4.1: Reduce Popup Polyfill to Minimal Guards

**Goal**: Let native APIs surface once background messaging is reliable

**What to do**:
- In `ExtensionManager.swift` popup script injection (the "CHROME API INJECTION" block):
  - Reduce polyfill to minimal guards
  - Keep only essential existence checks (e.g., `window.chrome = window.chrome || {}`)
  - Remove synthetic success returns for sendMessage
  - Remove verbose diagnostic logging (or gate behind debug flag)
- Add feature flag to control polyfill level for testing

**Files to modify**:
- `Nook/Managers/ExtensionManager/ExtensionManager.swift`
  - Popup webview script injection (around presentActionPopup delegate)

**Acceptance criteria**:
- Popup uses native `chrome.*` APIs
- Logs show real message round-trips
- No synthetic success messages
- Debug logging can be toggled with flag

**Estimated effort**: 0.5-1 day

---

### Task 4.2: Add file:// Host Permission Support

**Goal**: Enable extensions to access local HTML files if user permits

**What to build**:
- Verify permission prompt UI can display `file://` match patterns
- Ensure ExtensionManager grants/checks file access permissions correctly
- Test loading a `file://` URL and confirming content scripts inject
- Add UI to enable/disable file access per extension

**Files to modify**:
- `Nook/Managers/ExtensionManager/ExtensionManager.swift`
  - Permission granting logic (check for file:// patterns)
- Permission prompt UI view if needed
- Extension settings UI to toggle file access

**Testing**:
- Load a test extension
- Enable file:// access in extension settings
- Open a local HTML file
- Verify extension can access the page
- Check console for content script injection

**Acceptance criteria**:
- User can enable file access for extensions
- Extensions can access local HTML pages when enabled
- Permission prompt shows file:// access request
- Extension respects file access permission

**Estimated effort**: 1 day

---

### Task 4.3: Exercise test-extensions for Regression

**Goal**: Validate that changes don't break existing extension API surface

**What to do**:
- Load test extensions from `test-extensions/` directory
- Run through all test scenarios:
  - Runtime messaging
  - Storage (local/session)
  - Tabs API
  - Scripting API
  - Alarms
  - Clipboard (if applicable)
- Confirm all API bridges return expected results
- Add reference extensions (e.g., Dark Reader, uBlock Origin) as ongoing regression test cases
- Document test procedures

**Files to check**:
- `test-extensions/` directory contents
- Create test plan document if missing

**Acceptance criteria**:
- All test extensions pass their test scenarios
- No regressions from Phase 1-3 changes
- Reference extensions (Dark Reader, etc.) operate as expected
- Test results documented

**Estimated effort**: 1-2 days

---

## Phase 5: End-to-End Validation

### Task 5.1: Extension Installation and Smoke Test

**Test procedure**:
1. Load test extensions from:
   - Unpacked manifest (development mode)
   - Or CRX file from Chrome Web Store
2. Verify popup opens and renders correctly
3. Check popup UI is functional
4. Test core extension functionality
5. Restart Nook and verify settings persisted
6. Check console for errors or warnings

**Test with multiple extensions**:
- Dark Reader (content scripts, CSS injection, storage)
- uBlock Origin (if possible - complex extension)
- Simple test extensions from test-extensions/

**Expected results**:
- ✅ Popup opens without errors
- ✅ UI is fully functional
- ✅ chrome.runtime.getManifest() returns correct data
- ✅ Settings persist across browser restarts
- ✅ No console errors

**Estimated effort**: 0.5 day

---

### Task 5.2: Messaging Validation

**Test procedure**:
1. Open extension popup
2. Trigger action that sends message to background
3. Open browser developer console (if service worker console accessible)
4. Verify message received in service worker
5. Verify response flows back to popup
6. Check UI updates correctly
7. Repeat from content script (if applicable)

**Expected results**:
- ✅ Popup → background messages work
- ✅ Background → popup responses work
- ✅ Content → background messages work
- ✅ Console logs show real round-trips
- ✅ No synthetic "success: true" responses

**Estimated effort**: 0.5 day

---

### Task 5.3: Complex Page Testing

**Test procedure**:
1. Test on YouTube:
   - Verify extension content scripts inject
   - Check embedded ad iframes
   - Verify extension behavior works across frames
2. Test on Google Docs:
   - Verify editor iframe receives content scripts
   - Check toolbar and menus
   - Verify no flicker on interaction
3. Test on news sites with embedded content:
   - Verify all iframes receive content scripts
   - Check for timing issues

**Expected results**:
- ✅ Extension behavior applies to main frame and all iframes
- ✅ No flickering or timing race conditions
- ✅ Dynamic content handled correctly
- ✅ No console errors

**Estimated effort**: 0.5 day

---

### Task 5.4: Commands and Context Menu

**Test procedure**:
1. Configure keyboard shortcut in extension (if available)
2. Press hotkey and verify expected behavior
3. Right-click on page
4. Check for extension context menu item
5. Click menu item
6. Verify expected action executed

**Expected results**:
- ✅ Keyboard shortcut triggers expected extension behavior
- ✅ Context menu appears in right-click menu
- ✅ Menu click triggers expected extension action
- ✅ State persists correctly

**Estimated effort**: 0.5 day

---

### Task 5.5: Optional file:// Testing

**Test procedure**:
1. Enable file:// access in extension permissions
2. Create test HTML file locally
3. Open file in Nook (file:///path/to/test.html)
4. Verify extension works on local file

**Expected results**:
- ✅ File access permission can be granted
- ✅ Extensions work correctly on local HTML files
- ✅ Content scripts inject on file:// URLs

**Estimated effort**: 0.5 day

---

## Dependencies and Sequencing

### Parallel Work Opportunities
- **Phase 1 and Phase 2 can be parallelized**
  - Different engineers can work on messaging (Phase 1) vs injection (Phase 2)
  - No direct dependencies between these phases

### Sequential Dependencies
- **Phase 3 depends on Phase 1**
  - Messaging must work before commands/contextMenus can route events
  - Task 3.3 explicitly requires Task 1.1 and 1.3 complete

- **Phase 4 and 5 are sequential**
  - Polish and hardening after core functionality
  - End-to-end validation requires all previous phases complete

### Recommended Order
1. **Parallel**: Start Phase 1 (messaging) and Phase 2 (injection) simultaneously
2. **Sequential**: Complete Phase 3 after Phase 1 completes
3. **Sequential**: Complete Phase 4 after Phases 1-3 complete
4. **Sequential**: Complete Phase 5 (validation) last

---

## Effort Estimates

### By Phase
- **Phase 1**: 3-5 days (MessagePort plumbing is new, needs careful testing)
- **Phase 2**: 2-3 days (mostly verification and selective removal of manual code)
- **Phase 3**: 2-3 days (frame targeting and storage shim are straightforward)
- **Phase 4**: 1-2 days (polish and testing)
- **Phase 5**: 1-2 days (end-to-end validation)

### Total Time
- **Single engineer**: ~2 weeks (10 working days)
- **Two engineers** (parallelizing Phase 1 and 2): ~1 week (5 working days)

### Critical Path
Phase 1 → Phase 3 → Phase 4 → Phase 5 (longest dependency chain)

---

## Success Criteria

Chrome extensions will be considered "fully operational" when all of the following criteria are met:

### Core Functionality
- ✅ **Popup**: Opens consistently, shows correct UI, functions properly
- ✅ **Content Scripts**: Inject across main frame and iframes, with minimal flicker
- ✅ **Storage**: Settings persist across browser restarts and are read correctly by popup/content/background
- ✅ **Messaging**: Verified two-way messaging between popup/content and service worker (observable in logs)

### Optional Functionality
- ✅ **Commands**: Configured hotkeys trigger expected extension behavior without opening popup
- ✅ **Context menu**: If used, onClicked triggers expected action and state updates
- ✅ **File access**: Extensions work on file:// pages when enabled

### Quality Gates
- ✅ **No console errors** during normal operation
- ✅ **No synthetic responses** masking real communication failures
- ✅ **Real round-trip messaging** confirmed via console logs
- ✅ **No flickering** or timing issues on page load
- ✅ **Settings persistence** verified across browser restarts

---

## Notable Code References

### Background/Service Worker
- Background load attempt: `ExtensionManager.swift` (lines ~1100-1160)
- Missing background dispatch: `getBackgroundWebView()` in `ExtensionManager+ContextMenus.swift` (returns nil)

### Popup
- Popup wiring: `ExtensionManager.swift` (`presentActionPopup` delegate)
- Popup view: `Nook/Components/Extensions/ExtensionActionView.swift`

### API Bridges
- Runtime: `Nook/Managers/ExtensionManager/ExtensionManager+Runtime.swift`
- Tabs: `Nook/Managers/ExtensionManager/ExtensionManager+Tabs.swift`
- Scripting: `Nook/Managers/ExtensionManager/ExtensionManager+Scripting.swift`
- Storage: `Nook/Managers/ExtensionManager/ExtensionManager+Storage.swift`
- Action: `Nook/Managers/ExtensionManager/ExtensionManager+Action.swift`
- Commands: `Nook/Managers/ExtensionManager/ExtensionManager+Commands.swift`
- Context Menus: `Nook/Managers/ExtensionManager/ExtensionManager+ContextMenus.swift`

### Storage
- Storage manager: `Nook/Managers/ExtensionManager/ExtensionStorageManager.swift`

### Tab Registration
- Tab registration: `ExtensionManager.swift` (`registerAllExistingTabs` methods)

---

## Platform Requirements

### macOS Version
- **Minimum**: macOS 15.5+
- **Reason**: Required for WKWebExtension MessagePort APIs and MV3 service worker support
- **Verified in**: `ExtensionUtils.swift` guards

### Testing Environment
- All extension testing must occur on macOS 15.5 or newer
- Test on both Intel and Apple Silicon if possible

---

## Risk Assessment

### High Risk
- **MessagePort implementation** (Task 1.1)
  - New API surface, limited documentation
  - Mitigation: Start early, allocate extra time for experimentation

### Medium Risk
- **Native content script injection** (Phase 2)
  - Depends on correct WebView controller attachment timing
  - Mitigation: Add extensive logging, test thoroughly

- **Frame targeting** (Task 3.1)
  - Complex frame hierarchy traversal
  - Mitigation: Test on complex pages early (YouTube, Google Docs)

### Low Risk
- **Storage sync shim** (Task 3.2)
  - Simple aliasing, low complexity
  
- **Popup polyfill reduction** (Task 4.1)
  - Easy to revert if issues arise

---

## Future Enhancements (Out of Scope)

These are not required for Dark Reader to be "fully operational" but may be needed for other extensions:

- **chrome.storage.sync** real cloud synchronization
- **chrome.webRequest** / **chrome.declarativeNetRequest** APIs
- **chrome.downloads** API
- **chrome.history** API
- **chrome.bookmarks** API
- **chrome.cookies** API
- **Dynamic content scripts** registration (`chrome.scripting.registerContentScripts`)
- **Extension service worker** debugging UI

---

## Summary

The `feat/fix-extension-popup-loading` branch has built a solid native-first foundation for Chrome extension support in Nook. The architecture is well-designed and most components are in place.

**The main missing piece** is a reliable background/service worker messaging path via `WKWebExtension.MessagePort`. Once this is implemented (Phase 1), the remaining work is straightforward:
- Rely on native content script injection (Phase 2)
- Add frame targeting and storage sync (Phase 3)
- Polish and validate (Phases 4-5)

**Recommended approach**: Start Phase 1 and Phase 2 in parallel with two engineers, then proceed sequentially through Phases 3-5.

**Timeline**: With focused effort, Chrome extensions can be fully operational in 1-2 weeks.

**Validation**: Dark Reader will serve as the primary reference extension for testing, with additional testing on other popular extensions to ensure broad compatibility.

---

## Document Version

- **Version**: 1.0
- **Date**: 2025-10-16
- **Based on branch**: `feat/fix-extension-popup-loading`
- **Author**: Codegen AI
- **Status**: Ready for implementation
