# uBlock Origin Implementation Guide for Nook Browser

**Target**: Full support for uBlock Origin Lite (Manifest V3)  
**Timeline**: 3-4 weeks minimum viable product  
**Priority**: Critical for modern web browsing experience

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Required APIs Overview](#required-apis-overview)
3. [declarativeNetRequest Implementation](#declarativenetrequest-implementation)
4. [Storage API Implementation](#storage-api-implementation)
5. [Scripting API Implementation](#scripting-api-implementation)
6. [Tabs API Completion](#tabs-api-completion)
7. [WebNavigation API Implementation](#webnavigation-api-implementation)
8. [Integration Strategy](#integration-strategy)
9. [Testing Plan](#testing-plan)
10. [Performance Optimization](#performance-optimization)

---

## Executive Summary

uBlock Origin is one of the most popular browser extensions, with 40M+ users. Supporting it requires implementing three critical Chrome Extension APIs that are currently missing from Nook:

**Critical Path (Must Have)**:
1. **declarativeNetRequest** - Network request filtering (1-2 weeks)
2. **chrome.storage** - Data persistence (2-3 days)
3. **chrome.scripting** - DOM manipulation (2-3 days)

**Enhanced Features**:
4. **Tabs API completion** - Full tab control (1-2 days)
5. **WebNavigation** - Navigation tracking (2 days)

**Total Estimated Time**: 3-4 weeks for basic functionality, 5-6 weeks for full support

---

## Required APIs Overview

### Priority Matrix

| API | Priority | Status | Complexity | Time Est. | Blocker? |
|-----|----------|--------|------------|-----------|----------|
| declarativeNetRequest | 🔴 CRITICAL | 0% | HIGH | 1-2 weeks | YES |
| storage.local | 🔴 CRITICAL | 25% | MEDIUM | 2-3 days | YES |
| scripting | 🔴 HIGH | 0% | MEDIUM | 2-3 days | YES |
| tabs (complete) | 🟡 MEDIUM | 70% | LOW | 1-2 days | NO |
| webNavigation | 🟡 MEDIUM | 0% | MEDIUM | 2 days | NO |

### Dependencies Graph

```
declarativeNetRequest (core blocking)
    ↓
storage.local (rule persistence)
    ↓
tabs API (apply to tabs)
    ↓
scripting (cosmetic filtering)
    ↓
webNavigation (advanced features)
```

---

## declarativeNetRequest Implementation

### Overview

The `declarativeNetRequest` API is the cornerstone of modern content blocking in Manifest V3. It allows extensions to specify rules that the browser evaluates natively, without requiring persistent background processes.

### Architecture

```
Extension Manifest
    ↓
Rule Files (JSON)
    ↓
WKWebExtensionController
    ↓
Rule Compilation → WKContentRuleList (Apple Native!)
    ↓
WKWebView applies rules natively
```

### Key Advantage

**Apple already provides native content blocking** through `WKContentRuleList`! We can bridge declarativeNetRequest rules to this native system for maximum performance.

### API Surface

```javascript
// Chrome APIs to implement
chrome.declarativeNetRequest = {
  // Static rules from manifest
  updateEnabledRulesets(options, callback)
  getEnabledRulesets(callback)
  
  // Dynamic rules (runtime updates)
  updateDynamicRules(options, callback)
  getDynamicRules(callback)
  
  // Session rules (cleared on browser restart)
  updateSessionRules(options, callback)
  getSessionRules(callback)
  
  // Matched rules (debugging)
  getMatchedRules(filter, callback)
  onRuleMatchedDebug
  
  // Constants
  MAX_NUMBER_OF_STATIC_RULESETS: 100
  MAX_NUMBER_OF_ENABLED_STATIC_RULESETS: 50
  MAX_NUMBER_OF_DYNAMIC_RULES: 30000
  MAX_NUMBER_OF_UNSAFE_DYNAMIC_RULES: 5000
}
```

### Rule Format

```json
{
  "id": 1,
  "priority": 1,
  "action": {
    "type": "block" // or "allow", "redirect", "upgradeScheme", "modifyHeaders"
  },
  "condition": {
    "urlFilter": "||ads.example.com^",
    "resourceTypes": ["script", "image", "stylesheet"],
    "domains": ["example.com"],
    "excludedDomains": ["safe.example.com"]
  }
}
```

### Implementation Steps

#### Phase 1: Core Infrastructure (Days 1-3)

**File**: `Nook/Managers/ExtensionManager/DeclarativeNetRequestManager.swift`

```swift
@available(macOS 15.4, *)
class DeclarativeNetRequestManager {
    // Rule storage
    private var staticRules: [String: [DNRRule]] = [:] // extensionId -> rules
    private var dynamicRules: [String: [DNRRule]] = [:] 
    private var sessionRules: [String: [DNRRule]] = [:]
    
    // Compiled rule lists (Apple native)
    private var compiledRuleLists: [String: WKContentRuleList] = [:]
    
    // Rule limits
    static let MAX_STATIC_RULESETS = 100
    static let MAX_ENABLED_STATIC_RULESETS = 50
    static let MAX_DYNAMIC_RULES = 30_000
    static let MAX_UNSAFE_DYNAMIC_RULES = 5_000
    
    func loadStaticRules(for extensionId: String, from manifest: [String: Any])
    func updateDynamicRules(for extensionId: String, rules: [DNRRule])
    func compileRules(for extensionId: String) async throws -> WKContentRuleList
    func applyRulesToWebView(_ webView: WKWebView, extensionId: String)
}
```

#### Phase 2: Rule Compilation (Days 4-5)

Convert Chrome declarativeNetRequest format to Apple WKContentRuleList format:

```swift
struct DNRRule: Codable {
    let id: Int
    let priority: Int
    let action: DNRAction
    let condition: DNRCondition
}

struct DNRAction: Codable {
    let type: ActionType // block, allow, redirect, etc.
    let redirect: DNRRedirect?
}

struct DNRCondition: Codable {
    let urlFilter: String?
    let regexFilter: String?
    let resourceTypes: [ResourceType]?
    let domains: [String]?
    let excludedDomains: [String]?
}

func convertToWKContentRule(_ dnrRule: DNRRule) -> String {
    // Convert Chrome format to Apple format
    // Example: "||ads.com^" -> {"trigger": {"url-filter": ".*ads\\.com.*"}}
}
```

#### Phase 3: JavaScript Bridge (Days 6-7)

Inject `chrome.declarativeNetRequest` API into extension contexts:

```javascript
// Injected into background/popup contexts
chrome.declarativeNetRequest = {
  updateDynamicRules: function(options, callback) {
    return new Promise((resolve, reject) => {
      window.webkit.messageHandlers.declarativeNetRequest.postMessage({
        method: 'updateDynamicRules',
        addRules: options.addRules || [],
        removeRuleIds: options.removeRuleIds || []
      }).then(resolve).catch(reject);
    });
  },
  
  getDynamicRules: function(callback) {
    return new Promise((resolve) => {
      window.webkit.messageHandlers.declarativeNetRequest.postMessage({
        method: 'getDynamicRules'
      }).then(resolve);
    });
  }
};
```

#### Phase 4: Message Handler (Days 8-9)

Handle JavaScript calls in Swift:

```swift
extension ExtensionManager: WKScriptMessageHandler {
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "declarativeNetRequest" else { return }
        guard let body = message.body as? [String: Any] else { return }
        guard let method = body["method"] as? String else { return }
        
        switch method {
        case "updateDynamicRules":
            handleUpdateDynamicRules(body, message: message)
        case "getDynamicRules":
            handleGetDynamicRules(message: message)
        // ... other methods
        }
    }
    
    private func handleUpdateDynamicRules(_ body: [String: Any], message: WKScriptMessage) {
        let addRules = body["addRules"] as? [[String: Any]] ?? []
        let removeIds = body["removeRuleIds"] as? [Int] ?? []
        
        // Parse rules
        let rules = parseRules(addRules)
        
        // Update in manager
        Task {
            do {
                try await dnrManager.updateDynamicRules(
                    for: currentExtensionId,
                    add: rules,
                    remove: removeIds
                )
                message.webView?.evaluateJavaScript("Promise.resolve()")
            } catch {
                message.webView?.evaluateJavaScript("Promise.reject('\(error)')")
            }
        }
    }
}
```

#### Phase 5: Rule Matching & Application (Days 10-12)

Apply rules to all webviews:

```swift
func applyExtensionRules(to webView: WKWebView) {
    for (extensionId, ruleList) in compiledRuleLists {
        webView.configuration.userContentController.add(ruleList)
    }
}

// Trigger recompilation when rules change
func onRulesChanged(extensionId: String) {
    Task {
        let ruleList = try await dnrManager.compileRules(for: extensionId)
        compiledRuleLists[extensionId] = ruleList
        
        // Apply to all existing webviews
        BrowserManager.shared.allWebViews.forEach { webView in
            applyExtensionRules(to: webView)
        }
    }
}
```

### Rule Conversion Examples

#### Block Rule
```javascript
// Chrome format
{
  "id": 1,
  "action": {"type": "block"},
  "condition": {"urlFilter": "||ads.example.com^"}
}

// Apple WKContentRuleList format
{
  "trigger": {
    "url-filter": ".*ads\\.example\\.com.*"
  },
  "action": {
    "type": "block"
  }
}
```

#### Redirect Rule
```javascript
// Chrome format
{
  "id": 2,
  "action": {
    "type": "redirect",
    "redirect": {"url": "https://safe.com"}
  },
  "condition": {"urlFilter": "tracker.com"}
}

// Apple format
{
  "trigger": {
    "url-filter": ".*tracker\\.com.*"
  },
  "action": {
    "type": "redirect",
    "url": "https://safe.com"
  }
}
```

### Testing Strategy

1. **Unit Tests**: Rule parsing and conversion
2. **Integration Tests**: Rule application to webviews
3. **Real-World Tests**: Install uBlock Origin Lite
4. **Performance Tests**: 30,000+ rules loading time

### Performance Considerations

- **Lazy compilation**: Only compile rules when needed
- **Caching**: Cache compiled WKContentRuleLists
- **Incremental updates**: Only recompile changed rulesets
- **Background compilation**: Compile rules off main thread

### Estimated Timeline

| Task | Days | Dependencies |
|------|------|--------------|
| Core infrastructure | 3 | None |
| Rule compilation | 2 | Core |
| JavaScript bridge | 2 | Core |
| Message handlers | 2 | Bridge |
| Rule application | 3 | Compilation |
| Testing & debugging | 2 | All |
| **Total** | **14 days** | |

---

## Storage API Implementation

### Overview

The chrome.storage API provides persistent data storage for extensions. uBlock Origin uses it extensively for:
- Filter list storage
- User preferences
- Whitelist/blacklist data
- Statistics and metrics

### Current State

Framework exists (`ExtensionManager.swift` lines 2367-2515) but returns `nil`/stubs. Needs actual implementation.

### API Surface

```javascript
chrome.storage.local = {
  get(keys, callback)
  set(items, callback)
  remove(keys, callback)
  clear(callback)
  getBytesInUse(keys, callback)
  
  // Event listener
  onChanged.addListener((changes, areaName) => {})
}

// Constants
chrome.storage.local.QUOTA_BYTES = 10485760 // 10MB
```

### Implementation Strategy

Use Apple's `WKWebsiteDataStore` for persistence:

```swift
class ExtensionStorageManager {
    private var stores: [String: [String: Any]] = [:] // extensionId -> data
    private let fileManager = FileManager.default
    private let storageDirectory: URL
    
    init() {
        // Storage location: ~/Library/Application Support/Nook/Extensions/Storage/
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storageDirectory = appSupport.appendingPathComponent("Nook/Extensions/Storage")
        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Core Methods
    
    func get(for extensionId: String, keys: [String]?) async -> [String: Any] {
        let store = loadStore(for: extensionId)
        
        if let keys = keys {
            return keys.reduce(into: [:]) { result, key in
                result[key] = store[key]
            }
        }
        return store
    }
    
    func set(for extensionId: String, items: [String: Any]) async throws {
        var store = loadStore(for: extensionId)
        
        // Track changes for onChanged event
        var changes: [String: StorageChange] = [:]
        
        for (key, newValue) in items {
            let oldValue = store[key]
            store[key] = newValue
            changes[key] = StorageChange(oldValue: oldValue, newValue: newValue)
        }
        
        // Persist to disk
        try saveStore(store, for: extensionId)
        
        // Fire onChanged event
        notifyStorageChange(extensionId: extensionId, changes: changes)
    }
    
    func remove(for extensionId: String, keys: [String]) async throws {
        var store = loadStore(for: extensionId)
        var changes: [String: StorageChange] = [:]
        
        for key in keys {
            if let oldValue = store.removeValue(forKey: key) {
                changes[key] = StorageChange(oldValue: oldValue, newValue: nil)
            }
        }
        
        try saveStore(store, for: extensionId)
        notifyStorageChange(extensionId: extensionId, changes: changes)
    }
    
    // MARK: - Persistence
    
    private func loadStore(for extensionId: String) -> [String: Any] {
        let fileURL = storageDirectory.appendingPathComponent("\(extensionId).json")
        
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        
        return json
    }
    
    private func saveStore(_ store: [String: Any], for extensionId: String) throws {
        let fileURL = storageDirectory.appendingPathComponent("\(extensionId).json")
        let data = try JSONSerialization.data(withJSONObject: store, options: [.prettyPrinted])
        try data.write(to: fileURL)
    }
    
    // MARK: - Change Notifications
    
    private func notifyStorageChange(extensionId: String, changes: [String: StorageChange]) {
        // Post notification to extension contexts
        let script = """
        if (chrome.storage && chrome.storage.onChanged) {
            const changes = \(encodeJSON(changes));
            chrome.storage.onChanged._fire(changes, 'local');
        }
        """
        
        // Execute in all extension contexts (background, popup, content scripts)
        executeInExtensionContexts(extensionId: extensionId, script: script)
    }
}

struct StorageChange: Codable {
    let oldValue: Any?
    let newValue: Any?
}
```

### JavaScript Bridge

```javascript
// Inject into extension contexts
chrome.storage = {
  local: {
    get: function(keys, callback) {
      return new Promise((resolve, reject) => {
        window.webkit.messageHandlers.storage.postMessage({
          method: 'get',
          area: 'local',
          keys: Array.isArray(keys) ? keys : (keys ? [keys] : null)
        }).then(result => {
          if (callback) callback(result);
          resolve(result);
        }).catch(reject);
      });
    },
    
    set: function(items, callback) {
      return new Promise((resolve, reject) => {
        window.webkit.messageHandlers.storage.postMessage({
          method: 'set',
          area: 'local',
          items: items
        }).then(() => {
          if (callback) callback();
          resolve();
        }).catch(reject);
      });
    },
    
    remove: function(keys, callback) {
      return new Promise((resolve, reject) => {
        const keyArray = Array.isArray(keys) ? keys : [keys];
        window.webkit.messageHandlers.storage.postMessage({
          method: 'remove',
          area: 'local',
          keys: keyArray
        }).then(() => {
          if (callback) callback();
          resolve();
        }).catch(reject);
      });
    },
    
    clear: function(callback) {
      return new Promise((resolve, reject) => {
        window.webkit.messageHandlers.storage.postMessage({
          method: 'clear',
          area: 'local'
        }).then(() => {
          if (callback) callback();
          resolve();
        }).catch(reject);
      });
    },
    
    onChanged: {
      _listeners: [],
      addListener: function(callback) {
        this._listeners.push(callback);
      },
      _fire: function(changes, areaName) {
        this._listeners.forEach(cb => cb(changes, areaName));
      }
    }
  }
};
```

### Estimated Timeline

| Task | Days |
|------|------|
| Core storage manager | 1 |
| JavaScript bridge | 0.5 |
| Message handlers | 0.5 |
| Change notifications | 0.5 |
| Testing | 0.5 |
| **Total** | **3 days** |

---

## Scripting API Implementation

### Overview

The `chrome.scripting` API allows extensions to inject JavaScript and CSS into web pages. Critical for uBlock's cosmetic filtering (hiding ads visually).

### API Surface

```javascript
chrome.scripting = {
  executeScript(injection, callback)
  insertCSS(injection, callback)
  removeCSS(injection, callback)
  registerContentScripts(scripts)
  unregisterContentScripts(filter)
  getRegisteredContentScripts(filter, callback)
  updateContentScripts(scripts)
}

// Injection object structure
{
  target: {
    tabId: number,
    frameIds?: number[],
    allFrames?: boolean
  },
  func?: function, // JavaScript function
  args?: any[], // Arguments to function
  files?: string[], // JS/CSS files from extension
  css?: string, // Inline CSS
  origin?: 'USER' | 'AUTHOR'
}
```

### Implementation Strategy

Build on existing content script system:

```swift
class ScriptingAPIManager {
    weak var extensionManager: ExtensionManager?
    weak var browserManager: BrowserManager?
    
    // MARK: - Execute Script
    
    func executeScript(
        extensionId: String,
        target: ScriptTarget,
        function: String?,
        args: [Any]?,
        files: [String]?
    ) async throws -> [InjectionResult] {
        
        guard let tab = getTab(target.tabId) else {
            throw ScriptingError.invalidTab
        }
        
        var script: String
        
        if let function = function {
            // Wrap function with args
            let argsJSON = args?.toJSON() ?? "[]"
            script = "(\(function)).apply(null, \(argsJSON))"
        } else if let files = files {
            // Load and concatenate files from extension
            script = try loadScriptFiles(extensionId: extensionId, files: files)
        } else {
            throw ScriptingError.noScriptProvided
        }
        
        // Execute in target frames
        return try await executeInFrames(tab: tab, script: script, target: target)
    }
    
    private func executeInFrames(
        tab: Tab,
        script: String,
        target: ScriptTarget
    ) async throws -> [InjectionResult] {
        
        var results: [InjectionResult] = []
        
        if target.allFrames {
            // Execute in main frame and all iframes
            results.append(try await executeInMainFrame(tab: tab, script: script))
            results.append(contentsOf: try await executeInAllIframes(tab: tab, script: script))
        } else if let frameIds = target.frameIds {
            // Execute in specific frames
            for frameId in frameIds {
                results.append(try await executeInFrame(tab: tab, frameId: frameId, script: script))
            }
        } else {
            // Execute in main frame only (default)
            results.append(try await executeInMainFrame(tab: tab, script: script))
        }
        
        return results
    }
    
    private func executeInMainFrame(tab: Tab, script: String) async throws -> InjectionResult {
        return try await withCheckedThrowingContinuation { continuation in
            tab.webView?.evaluateJavaScript(script) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: InjectionResult(
                        frameId: 0,
                        result: result
                    ))
                }
            }
        }
    }
    
    // MARK: - Insert CSS
    
    func insertCSS(
        extensionId: String,
        target: ScriptTarget,
        css: String?,
        files: [String]?,
        origin: CSSOrigin
    ) async throws {
        
        var cssContent: String
        
        if let css = css {
            cssContent = css
        } else if let files = files {
            cssContent = try loadCSSFiles(extensionId: extensionId, files: files)
        } else {
            throw ScriptingError.noCSSProvided
        }
        
        // Inject CSS as <style> tag
        let script = """
        (function() {
            const style = document.createElement('style');
            style.textContent = `\(escapedCSS(cssContent))`;
            style.setAttribute('data-extension-id', '\(extensionId)');
            style.setAttribute('data-origin', '\(origin.rawValue)');
            \(origin == .user ? "document.documentElement" : "document.head").appendChild(style);
            return style.id;
        })()
        """
        
        _ = try await executeScript(
            extensionId: extensionId,
            target: target,
            function: script,
            args: nil,
            files: nil
        )
    }
    
    // MARK: - Remove CSS
    
    func removeCSS(
        extensionId: String,
        target: ScriptTarget,
        css: String?,
        files: [String]?
    ) async throws {
        
        // Find and remove matching <style> tags
        let script = """
        (function() {
            const styles = document.querySelectorAll(
                'style[data-extension-id="\(extensionId)"]'
            );
            styles.forEach(style => style.remove());
        })()
        """
        
        _ = try await executeScript(
            extensionId: extensionId,
            target: target,
            function: script,
            args: nil,
            files: nil
        )
    }
}

struct ScriptTarget {
    let tabId: Int
    let frameIds: [Int]?
    let allFrames: Bool
}

struct InjectionResult {
    let frameId: Int
    let result: Any?
}

enum CSSOrigin: String {
    case user = "USER"
    case author = "AUTHOR"
}
```

### JavaScript Bridge

```javascript
chrome.scripting = {
  executeScript: function(injection, callback) {
    return new Promise((resolve, reject) => {
      window.webkit.messageHandlers.scripting.postMessage({
        method: 'executeScript',
        target: injection.target,
        func: injection.func ? injection.func.toString() : null,
        args: injection.args || [],
        files: injection.files || []
      }).then(results => {
        if (callback) callback(results);
        resolve(results);
      }).catch(reject);
    });
  },
  
  insertCSS: function(injection, callback) {
    return new Promise((resolve, reject) => {
      window.webkit.messageHandlers.scripting.postMessage({
        method: 'insertCSS',
        target: injection.target,
        css: injection.css,
        files: injection.files,
        origin: injection.origin || 'AUTHOR'
      }).then(() => {
        if (callback) callback();
        resolve();
      }).catch(reject);
    });
  },
  
  removeCSS: function(injection, callback) {
    return new Promise((resolve, reject) => {
      window.webkit.messageHandlers.scripting.postMessage({
        method: 'removeCSS',
        target: injection.target,
        css: injection.css,
        files: injection.files
      }).then(() => {
        if (callback) callback();
        resolve();
      }).catch(reject);
    });
  }
};
```

### Usage Example (uBlock)

```javascript
// Hide ads by CSS selector
chrome.scripting.insertCSS({
  target: {tabId: tab.id},
  css: '.ad-container, .sponsored-content { display: none !important; }'
});

// Remove tracking scripts
chrome.scripting.executeScript({
  target: {tabId: tab.id},
  func: () => {
    document.querySelectorAll('script[src*="tracker"]').forEach(s => s.remove());
  }
});
```

### Estimated Timeline

| Task | Days |
|------|------|
| Core scripting manager | 1 |
| executeScript implementation | 1 |
| insertCSS/removeCSS | 0.5 |
| JavaScript bridge | 0.5 |
| Testing | 0.5 |
| **Total** | **3.5 days** |

---

## Integration Strategy

### Phase-Based Implementation

#### Phase 1: Foundation (Week 1) - Storage API
**Goal**: Get data persistence working

**Tasks**:
1. Implement `ExtensionStorageManager.swift`
2. Add JavaScript bridge for `chrome.storage`
3. Test with `test-storage` extension
4. Verify persistence across browser restarts

**Success Criteria**:
- ✅ `chrome.storage.local.set()` works
- ✅ `chrome.storage.local.get()` works
- ✅ Data persists after restart
- ✅ `onChanged` events fire correctly

---

#### Phase 2: Network Blocking (Weeks 2-3) - declarativeNetRequest
**Goal**: Get basic ad/tracker blocking working

**Tasks**:
1. Create `DeclarativeNetRequestManager.swift`
2. Implement rule parsing (Chrome → WKContentRuleList)
3. Add JavaScript bridge for `chrome.declarativeNetRequest`
4. Implement static rules loading from manifest
5. Implement dynamic rules API
6. Test with simple blocking rules

**Success Criteria**:
- ✅ Static rules load from extension manifest
- ✅ Rules compile to WKContentRuleList
- ✅ Network requests are blocked correctly
- ✅ Dynamic rules can be added/removed at runtime
- ✅ 30,000+ rules handled efficiently

**Key Files**:
- `DeclarativeNetRequestManager.swift` (new)
- `ExtensionManager+DNR.swift` (extension)
- Update `loadExtension()` to load static rules

---

#### Phase 3: Cosmetic Filtering (Week 4) - Scripting API
**Goal**: Get visual ad removal working

**Tasks**:
1. Create `ScriptingAPIManager.swift`
2. Implement `executeScript()` with frame targeting
3. Implement `insertCSS()` / `removeCSS()`
4. Add JavaScript bridge for `chrome.scripting`
5. Test CSS injection and DOM manipulation

**Success Criteria**:
- ✅ `executeScript()` works in tabs
- ✅ `insertCSS()` hides elements
- ✅ Frame targeting works (allFrames, specific frames)
- ✅ Cosmetic filters applied correctly

---

#### Phase 4: Tabs & Navigation (Week 5) - Polish
**Goal**: Complete remaining APIs

**Tasks**:
1. Complete `chrome.tabs` API
   - `tabs.sendMessage()` to content scripts
   - Full `tabs.query()` filtering
   - `tabs.reload()` method
2. Implement basic `chrome.webNavigation`
   - `onBeforeNavigate`
   - `onCommitted`
   - `onCompleted`
3. Performance optimization

**Success Criteria**:
- ✅ Extensions can communicate with tabs
- ✅ Navigation events fire correctly
- ✅ All test extensions pass

---

### File Structure

```
Nook/Managers/ExtensionManager/
├── ExtensionManager.swift (existing)
├── ExtensionStorageManager.swift (new - Week 1)
├── DeclarativeNetRequestManager.swift (new - Weeks 2-3)
├── ScriptingAPIManager.swift (new - Week 4)
├── ExtensionManager+Storage.swift (extension)
├── ExtensionManager+DNR.swift (extension)
└── ExtensionManager+Scripting.swift (extension)
```

---

## Testing Plan

### Unit Tests

```swift
// StorageManagerTests.swift
class ExtensionStorageManagerTests: XCTestCase {
    func testSetAndGet() async throws {
        let manager = ExtensionStorageManager()
        try await manager.set(for: "test-ext", items: ["key": "value"])
        let result = await manager.get(for: "test-ext", keys: ["key"])
        XCTAssertEqual(result["key"] as? String, "value")
    }
    
    func testPersistence() async throws {
        let manager1 = ExtensionStorageManager()
        try await manager1.set(for: "test-ext", items: ["persist": "data"])
        
        // Create new instance (simulates restart)
        let manager2 = ExtensionStorageManager()
        let result = await manager2.get(for: "test-ext", keys: ["persist"])
        XCTAssertEqual(result["persist"] as? String, "data")
    }
}

// DeclarativeNetRequestManagerTests.swift
class DNRManagerTests: XCTestCase {
    func testRuleParsing() throws {
        let rule = DNRRule(
            id: 1,
            priority: 1,
            action: DNRAction(type: .block),
            condition: DNRCondition(urlFilter: "||ads.com^", resourceTypes: ["script"])
        )
        
        let wkRule = convertToWKContentRule(rule)
        XCTAssertTrue(wkRule.contains("url-filter"))
        XCTAssertTrue(wkRule.contains("block"))
    }
    
    func testRuleCompilation() async throws {
        let manager = DeclarativeNetRequestManager()
        let rules = [/* ... */]
        let ruleList = try await manager.compileRules(for: "test-ext")
        XCTAssertNotNil(ruleList)
    }
}
```

### Integration Tests

```swift
class ExtensionIntegrationTests: XCTestCase {
    func testUBlockInstallation() async throws {
        // Install uBlock Origin Lite
        let ubloURL = URL(fileURLWithPath: "/path/to/ublock-lite.crx")
        try await ExtensionManager.shared.installExtension(from: ubloURL)
        
        // Verify installation
        let extensions = ExtensionManager.shared.installedExtensions
        XCTAssertTrue(extensions.contains(where: { $0.name.contains("uBlock") }))
    }
    
    func testAdBlocking() async throws {
        // Load page with ads
        let webView = WKWebView()
        let url = URL(string: "https://example.com/page-with-ads")!
        webView.load(URLRequest(url: url))
        
        // Wait for page load
        await webView.waitForLoad()
        
        // Verify ad elements are blocked
        let adCount = try await webView.evaluateJavaScript(
            "document.querySelectorAll('.ad').length"
        ) as! Int
        XCTAssertEqual(adCount, 0, "Ads should be blocked")
    }
}
```

### Manual Testing Checklist

#### Storage API
- [ ] Install test-storage extension
- [ ] Save data and verify it persists
- [ ] Restart browser and verify data still there
- [ ] Clear storage and verify data removed
- [ ] Verify onChanged events fire

#### declarativeNetRequest
- [ ] Install uBlock Origin Lite
- [ ] Visit ad-heavy website (e.g., forbes.com)
- [ ] Verify ads are blocked
- [ ] Check network tab - requests blocked
- [ ] Add custom blocking rule
- [ ] Verify dynamic rule works

#### Scripting API
- [ ] Install extension that hides elements
- [ ] Verify CSS injection works
- [ ] Verify executeScript works
- [ ] Test in iframes (allFrames: true)
- [ ] Verify removeCSS works

---

## Performance Optimization

### Rule Compilation

```swift
class DNROptimizer {
    // Cache compiled rule lists
    private var compilationCache: [String: (rules: [DNRRule], compiled: WKContentRuleList)] = [:]
    
    func compileWithCache(rules: [DNRRule], for extensionId: String) async throws -> WKContentRuleList {
        let rulesHash = hashRules(rules)
        
        if let cached = compilationCache[rulesHash] {
            return cached.compiled
        }
        
        let compiled = try await actuallyCompile(rules)
        compilationCache[rulesHash] = (rules, compiled)
        return compiled
    }
    
    // Compile in background
    func precompileRules(for extensions: [Extension]) async {
        await withTaskGroup(of: Void.self) { group in
            for ext in extensions {
                group.addTask {
                    try? await self.compileRules(for: ext.id)
                }
            }
        }
    }
}
```

### Memory Management

```swift
// Limit rule list cache size
class RuleListCache {
    private var cache: [String: WKContentRuleList] = [:]
    private let maxCacheSize = 50 // MBs
    
    func add(_ ruleList: WKContentRuleList, for key: String) {
        // Evict oldest if over limit
        if estimatedSize() > maxCacheSize {
            evictOldest()
        }
        cache[key] = ruleList
    }
}
```

### Lazy Loading

```swift
// Only load rules when extension is enabled
func enableExtension(_ extensionId: String) {
    guard let ext = extensions[extensionId] else { return }
    
    Task {
        // Load and compile rules in background
        if ext.hasDeclarativeNetRequest {
            try? await dnrManager.loadRules(for: extensionId)
        }
        
        // Apply to active webviews
        applyExtensionToAllWebViews(extensionId)
    }
}
```

---

## Timeline Summary

### Minimum Viable Product (Basic Blocking)

| Week | Focus | Deliverables | Days |
|------|-------|--------------|------|
| 1 | Storage API | Persistent data storage working | 5 |
| 2-3 | declarativeNetRequest | Basic network blocking working | 10 |
| | | **Total: 3 weeks** | **15** |

**After 3 weeks**: Basic ad blocking works, but no cosmetic filtering

---

### Full Feature Set

| Week | Focus | Deliverables | Days |
|------|-------|--------------|------|
| 1 | Storage API | Persistent storage | 5 |
| 2-3 | declarativeNetRequest | Network blocking | 10 |
| 4 | Scripting API | Cosmetic filtering | 5 |
| 5 | Polish | Tabs, navigation, optimization | 5 |
| | | **Total: 5 weeks** | **25** |

**After 5 weeks**: Full uBlock Origin Lite support with all features

---

## Success Metrics

### MVP Success (3 weeks)
- ✅ Install uBlock Origin Lite without errors
- ✅ Block 90%+ of ads on test sites
- ✅ Filter lists load and persist
- ✅ Dynamic rules work
- ✅ No performance degradation (<50ms page load impact)

### Full Success (5 weeks)
- ✅ All of MVP +
- ✅ Cosmetic filtering works (elements hidden)
- ✅ Advanced features (tab integration, navigation tracking)
- ✅ 95%+ ad blocking rate
- ✅ Extension UI fully functional
- ✅ Multiple content blocking extensions work simultaneously

---

## Risk Mitigation

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| WKContentRuleList format incompatibility | MEDIUM | HIGH | Build conversion layer, extensive testing |
| Performance issues with 30K+ rules | MEDIUM | MEDIUM | Lazy loading, caching, background compilation |
| Rule syntax edge cases | HIGH | MEDIUM | Comprehensive test suite, iterate |
| Storage quota issues | LOW | LOW | Implement quota management |

### Schedule Risks

| Risk | Mitigation |
|------|------------|
| Underestimated complexity | Buffer time in estimates, prioritize ruthlessly |
| Scope creep | Stick to MVP, defer nice-to-haves |
| Dependencies/blockers | Parallel development where possible |

---

## Next Steps

### Immediate Actions (This Week)

1. **Review this document** with team
2. **Set up development branch**: `feat/ublock-apis`
3. **Create tracking issues** for each phase
4. **Start Phase 1**: StorageAPI implementation
5. **Set up test environment** with uBlock Origin Lite downloaded

### Week 1 Goals

- [ ] `ExtensionStorageManager.swift` created
- [ ] Storage API bridge implemented
- [ ] Unit tests passing
- [ ] test-storage extension working
- [ ] Begin DNR architecture planning

---

## Appendix: Useful Resources

### Documentation
- [Chrome declarativeNetRequest API](https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest)
- [Chrome storage API](https://developer.chrome.com/docs/extensions/reference/api/storage)
- [Chrome scripting API](https://developer.chrome.com/docs/extensions/reference/api/scripting)
- [Apple WKContentRuleList](https://developer.apple.com/documentation/webkit/wkcontentrulelist)
- [uBlock Origin Lite GitHub](https://github.com/uBlockOrigin/uBOL-home)

### Test Extensions
- [uBlock Origin Lite](https://chrome.google.com/webstore/detail/ublock-origin-lite/ddkjiahejlhfcafbddmgiahcphecmpfh)
- EasyList filter list: https://easylist.to/easylist/easylist.txt

### Tools
- Chrome Extension unpacker
- WKContentRuleList validator
- Performance profiling tools

---

**Document Version**: 1.0  
**Last Updated**: 2025-10-14  
**Author**: Codegen AI  
**Status**: Ready for Implementation

