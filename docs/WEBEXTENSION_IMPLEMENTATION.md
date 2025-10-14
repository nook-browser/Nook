# WebExtension Implementation Status

## Overview

This document tracks the implementation progress of WebExtension support in Nook browser, based on Apple's WKWebExtension framework (macOS 15.4+).

**Last Updated:** 2025-01-14  
**Implementation Phase:** Phase 3 - Core API Implementation  
**Overall Progress:** ~40% Complete

---

## ✅ Completed (Phase 1-3)

### Phase 1: Code Audit & Cleanup
- ✅ Identified all `MainActor.assumeIsolated` usage (4 instances in ExtensionBridge.swift)
- ✅ Documented threading issues and root causes
- ✅ Created comprehensive test extension suite

### Phase 2: Test Infrastructure
- ✅ **test-message-passing**: Tests `runtime.sendMessage` and message passing
- ✅ **test-storage**: Tests `chrome.storage.local` API
- ✅ **test-tab-events**: Tests tab lifecycle events (onCreated, onUpdated, onRemoved)
- ✅ **test-content-script**: Tests content script injection and DOM access

### Phase 3: Threading Fixes
- ✅ Removed `MainActor.assumeIsolated` from `ExtensionWindowAdapter.activeTab()`
- ✅ Removed `MainActor.assumeIsolated` from `ExtensionWindowAdapter.tabs()`
- ✅ Removed `MainActor.assumeIsolated` from `ExtensionTabAdapter.window()`
- ✅ Added nonisolated helper methods: `getStableAdapter()` and `getWindowAdapter()`
- ✅ Proper async/await patterns in place

**Impact:** Eliminates potential race conditions and crashes from improper MainActor isolation

---

## 🚧 In Progress (Phase 4-6)

### Phase 4: Message Passing Implementation ⚠️ **CRITICAL**
**Status:** NOT YET IMPLEMENTED

Extensions are essentially non-functional without message passing. This is the highest priority.

**Required:**
- [ ] Implement `WKWebExtensionControllerDelegate` message handling:
  ```swift
  func webExtensionController(_ controller: WKWebExtensionController,
                            receivedMessage message: Any,
                            from context: WKWebExtensionContext,
                            completionHandler: @escaping (Any?, Error?) -> Void)
  ```
- [ ] Add message routing system (popup ↔ background ↔ content scripts)
- [ ] Support `runtime.sendMessage()` API
- [ ] Support `tabs.sendMessage()` API
- [ ] Handle response callbacks properly
- [ ] Add comprehensive logging for debugging

**Validation:** test-message-passing extension should work end-to-end

### Phase 5: Storage API Implementation
**Status:** NOT YET IMPLEMENTED

**Required:**
- [ ] Implement `chrome.storage.local.get()`
- [ ] Implement `chrome.storage.local.set()`
- [ ] Implement `chrome.storage.local.remove()`
- [ ] Implement `chrome.storage.local.clear()`
- [ ] Add per-extension storage isolation using UserDefaults or file storage
- [ ] Optional: Add storage quota management (5MB limit)

**Validation:** test-storage extension should persist data across popup reopens

### Phase 6: Tab Lifecycle Events
**Status:** PARTIALLY IMPLEMENTED

Current implementation has `didOpenTab()`, `didCloseTab()`, etc. but they may not fire at the correct times.

**Required:**
- [ ] Wire up `tabs.onCreated` in TabManager when tabs are created
- [ ] Wire up `tabs.onRemoved` in TabManager when tabs are closed
- [ ] Wire up `tabs.onUpdated` when URL/title changes
- [ ] Wire up `tabs.onActivated` when user switches tabs
- [ ] Test edge cases (tab restoration, pinned tabs, etc.)

**Validation:** test-tab-events extension should log all tab operations correctly

---

## 📋 Planned (Phase 7-10)

### Phase 7: Content Script Verification
**Status:** UNKNOWN - NEEDS TESTING

Current implementation may rely on WKWebExtension framework auto-injection.

**Required:**
- [ ] Verify content scripts inject automatically
- [ ] Test with test-content-script extension
- [ ] Verify `run_at` timing (document_start, document_end, document_idle)
- [ ] Verify match patterns work correctly
- [ ] Add manual injection if framework doesn't handle it

**Validation:** test-content-script should show banner on all pages

### Phase 8: Popup Resource Loading Fix
**Status:** NEEDS FIX - Currently using JavaScript injection band-aid

Current code injects ~200 lines of JavaScript to "fix" popup resource loading. This suggests the root cause isn't addressed.

**Required:**
- [ ] Remove JavaScript injection workaround
- [ ] Ensure `webExtensionController` is set BEFORE popup WebView loads
- [ ] Verify `webkit-extension://` protocol works
- [ ] Test `chrome.runtime.getURL()` returns correct URLs
- [ ] Verify CSS, images, and scripts load properly

**Validation:** Popup should load all resources without injected scripts

### Phase 9: Background Script/Service Worker Support
**Status:** UNKNOWN - NEEDS INVESTIGATION

**Critical Questions:**
- Does WKWebExtension support service workers (MV3)?
- Are background pages (MV2) supported?
- How do we initialize them?

**Required:**
- [ ] Verify background script initialization
- [ ] Check if `context.backgroundContent` exists and loads
- [ ] Handle MV2 vs MV3 differences
- [ ] Test `chrome.runtime.onInstalled` event
- [ ] Test long-running vs. ephemeral background contexts

**Validation:** test-message-passing background script should respond to messages

### Phase 10: Real Extension Testing & Documentation
**Status:** NOT STARTED

**Required:**
- [ ] Test with uBlock Origin Lite (MV3)
- [ ] Test with other real-world extensions
- [ ] Document what works and what doesn't
- [ ] Create compatibility matrix
- [ ] List unsupported APIs
- [ ] Document known limitations

**Deliverable:** `WEBEXTENSION_SUPPORT.md` with compatibility guide

---

## 🔍 Known Issues

### Threading Issues (FIXED ✅)
- **Issue:** `MainActor.assumeIsolated` used in 4 places
- **Status:** FIXED in Phase 3
- **Solution:** Added nonisolated helper methods with proper MainActor boundaries

### Message Passing (NOT IMPLEMENTED ❌)
- **Issue:** Extensions cannot communicate between components
- **Status:** CRITICAL - Blocks most extension functionality
- **Priority:** HIGHEST

### Storage API (NOT IMPLEMENTED ❌)
- **Issue:** Extensions cannot persist state
- **Status:** HIGH PRIORITY - Many extensions need this
- **Priority:** HIGH

### Popup Resource Loading (BAND-AID 🩹)
- **Issue:** ~200 lines of JavaScript injection to "fix" loading
- **Status:** Works but indicates root cause not addressed
- **Priority:** MEDIUM

### Content Script Injection (UNKNOWN ❓)
- **Issue:** Not verified if framework handles this automatically
- **Status:** Needs testing
- **Priority:** HIGH

### Background Scripts (UNKNOWN ❓)
- **Issue:** Unclear if MV3 service workers are supported
- **Status:** Needs investigation
- **Priority:** HIGH

---

## 📊 API Compatibility Matrix

### Fully Supported ✅
- Extension loading/unloading
- Basic extension lifecycle
- Tab adapter pattern
- Window adapter pattern
- Data store sharing (critical for network requests)

### Partially Supported ⚠️
- Tab events (implemented but may not fire correctly)
- Popup display (works with JavaScript injection band-aid)

### Not Yet Implemented ❌
- `runtime.sendMessage()`
- `runtime.onMessage`
- `chrome.storage.local.*`
- `tabs.sendMessage()`
- Content script injection (needs verification)
- Background script initialization (needs verification)
- WebNavigation events

### Unknown / Needs Investigation ❓
- Service worker support (MV3)
- `chrome.storage.sync`
- `declarativeNetRequest` API
- `webRequest` API
- Browser action badge text/color
- Context menus

---

## 🎯 Success Criteria

### Minimum Viable Product (MVP)
- ✅ Test extensions load without errors
- ❌ Message passing works (popup ↔ background ↔ content)
- ❌ Storage API persists data
- ❌ Tab events fire correctly
- ❌ Content scripts inject and run
- ❌ Background scripts initialize

### Full Support
- All MVP criteria met
- At least one real-world extension works (e.g., uBlock Origin Lite)
- Documentation complete
- Known limitations documented
- Compatibility matrix published

---

## 💡 Notes for Developers

### Testing Workflow
1. Load test extension from `test-extensions/` directory
2. Check browser console for logs
3. For popups: Right-click popup → Inspect → Console
4. For background: Check main browser console
5. For content scripts: Check page inspector console

### Common Debugging
- **No logs?** Extension didn't load properly
- **Message passing fails?** Background script not running or delegate not implemented
- **Storage doesn't persist?** Data store configuration issue
- **Content script not injecting?** Check permissions and match patterns

### Architecture Notes
- `ExtensionManager` is the main coordinator (@MainActor)
- `ExtensionBridge.swift` contains adapter implementations
- `ExtensionWindowAdapter` bridges window APIs
- `ExtensionTabAdapter` bridges tab APIs
- All extension contexts share data stores with browser (critical fix)

### Performance Considerations
- Tab adapter caching prevents duplicate objects
- Stable adapters used for lifecycle events
- Data store sharing enables network requests

---

## 📚 Related Documentation

- [Test Extension README](../test-extensions/README.md) - How to use test extensions
- Apple's WKWebExtension Documentation (when available)
- [Chrome Extension API Reference](https://developer.chrome.com/docs/extensions/reference/)

---

## 🚀 Next Steps

**Immediate (Phase 4):**
1. Implement message passing infrastructure
2. Validate with test-message-passing extension
3. Add comprehensive logging

**Short-term (Phase 5-6):**
4. Implement storage API
5. Fix tab lifecycle event wiring
6. Test with all test extensions

**Medium-term (Phase 7-9):**
7. Verify content script injection
8. Fix popup resource loading properly
9. Investigate background script support

**Long-term (Phase 10):**
10. Test with real extensions
11. Document limitations
12. Create compatibility guide

---

**Questions or Issues?** Check the implementation code comments or open an issue.

