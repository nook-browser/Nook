# Extension System (WKWebExtension)

Deep documentation for Nook's web extension subsystem. For project-level context, see the [root CLAUDE.md](../../../CLAUDE.md).

## Availability

Deployment target is macOS 26.0, so WKWebExtension (15.4+) and content scripts (15.5+) are always available. No `@available` / `#available` guards are needed or wanted in extension code.

## Key Files

| File | Purpose |
|------|---------|
| `ExtensionManager.swift` | Core facade (~435 lines): properties, init/deinit, setup, profile stores, context identity |
| `ExtensionManager+Installation.swift` | Install flow, persistence, Safari discovery, Chrome Web Store, enable/disable/uninstall, MV3 support |
| `ExtensionManager+Delegate.swift` | All `WKWebExtensionControllerDelegate` methods: popup, permissions, tabs/windows, options page, native messaging |
| `ExtensionManager+ExternallyConnectable.swift` | Bridge JS generation for `externally_connectable`, manifest patching for WebKit |
| `ExtensionManager+Diagnostics.swift` | Background health probes, state diagnosis, popup diagnostics, testing helpers |
| `ExtensionManager+TabNotifications.swift` | Tab adapter management, tab lifecycle notifications, action anchor tracking |
| `NativeMessagingHandler.swift` | Standalone class: launches native host processes, stdin/stdout messaging protocol |
| `BitwardenBiometricHandler.swift` | In-process host for Bitwarden's `.appex` `connectNative("com.8bit.bitwarden")` biometric unlock: prompts Touch ID (LocalAuthentication) and returns the symmetric key from the `Bitwarden_biometric` Keychain service, so no Bitwarden desktop app is required |
| `InternalNativePortHandler.swift` | Small protocol for in-process native message port handlers |
| `PopupUIDelegate.swift` | `PopupClipboardHandler` (JS↔native clipboard bridge via WKScriptMessageHandler) + `PopupUIDelegate` (WKUIDelegate for popup webviews) |
| `ExtensionBridge.swift` | `WKWebExtensionTab` / `WKWebExtensionWindow` protocol adapters |
| `Nook/Models/Extension/ExtensionModels.swift` | `ExtensionEntity` (SwiftData) + `InstalledExtension` runtime model |
| `Nook/Models/BrowserConfig/BrowserConfig.swift` | Shared `WKWebViewConfiguration` factory — extension controller lives here |
| `Nook/Components/Extensions/ExtensionActionView.swift` | Toolbar buttons, popup anchor positioning |
| `Nook/Components/Extensions/ExtensionPermissionView.swift` | Permission grant/deny dialogs |
| `Nook/Components/Extensions/PopupConsoleWindow.swift` | Debug console for extension popups |
| `Nook/Utils/ExtensionUtils.swift` | Manifest validation, version checks |

## Critical: WebView Config Derivation

Tab webview configs **MUST** derive from the same `WKWebViewConfiguration` that the `WKWebExtensionController` was configured with (via `.copy()`). Creating a fresh `WKWebViewConfiguration()` and just setting `webExtensionController` on it is **NOT** enough — WebKit needs the config to share the same process pool / internal state.

The chain:
```
BrowserConfig.shared.webViewConfiguration  (base)
  → ExtensionManager sets .webExtensionController on it
  → webViewConfiguration(for: profile) calls .copy() + sets profile-specific data store
  → tab gets that derived config
```

See `BrowserConfig.swift:webViewConfiguration(for:)`.

## Installation Flow

Supported formats: `.zip`, `.appex` (Safari extension bundle), `.app` (scans `Contents/PlugIns/` for `.appex`), bare directories.

1. Extract/resolve source to get `manifest.json`
2. `ExtensionUtils.validateManifest()` — checks required fields
3. MV3 validation — verifies `background.service_worker` exists
4. `patchManifestForWebKit()` — patches world isolation, injects externally_connectable bridge
5. Create temporary `WKWebExtension` to get `uniqueIdentifier`
6. Move to `~/Library/Application Support/Nook/Extensions/{extensionId}/`
7. Grant ALL manifest permissions + host_permissions at install time (Chrome-like model)
8. Load background service worker immediately
9. Extract icon (128/64/48/32/16px from manifest icons), resolve `__MSG_key__` locale strings

## Externally Connectable Bridge

**Problem**: Pages like `account.proton.me` call `browser.runtime.sendMessage(SAFARI_EXT_ID, msg)` but Safari extension IDs don't match WKWebExtension IDs.

**Solution** (`setupExternallyConnectableBridge`): Two-layer bridge injected as content scripts:
- **PAGE world script**: Wraps `browser.runtime.sendMessage()` and `.connect()`, relays via `window.postMessage()` to the isolated world
- **ISOLATED world script** (`nook_bridge.js`): Receives postMessages, calls the real `browser.runtime.sendMessage()`, forwards responses back

`patchManifestForWebKit()` auto-injects the bridge content script entry into `manifest.json` when `externally_connectable` is present.

## Extension Bridge (ExtensionBridge.swift)

- **`ExtensionWindowAdapter`** implements `WKWebExtensionWindow`: exposes active tab, tab list, window state (minimized/maximized/fullscreen), focus/close operations, privacy status.
- **`ExtensionTabAdapter`** implements `WKWebExtensionTab`: exposes url, title, selection state, loading, pinned, muted, audio state. Returns `tab.assignedWebView` (does NOT trigger lazy init). Stable adapters cached in `tabAdapters` dictionary by `Tab.id`.

## Tab <> Extension Notification

Tab notifies the extension system after webview creation:
```
Tab.setupWebView()
  -> ExtensionManager.shared.notifyTabOpened(tab)  // controller.didOpenTab(adapter)
  -> If active: notifyTabActivated()                // controller.didActivateTab(adapter)
  -> tab.didNotifyOpenToExtensions = true
```

## Permission Model

- **Install-time**: ALL manifest `permissions` + `host_permissions` auto-granted (matching Chrome behavior)
- **On load (existing extensions)**: Grants both requested + optional permissions/match patterns, enables Web Inspector
- **Runtime** (`chrome.permissions.request`): Triggers `ExtensionPermissionView` dialog via delegate

## Storage Isolation

- Extensions installed globally (`~/Library/Application Support/Nook/Extensions/{id}/`)
- Runtime storage (`chrome.storage.*`, cookies, indexedDB) isolated per profile via separate `WKWebsiteDataStore`
- On profile switch: `controller.configuration.defaultWebsiteDataStore` updated to profile-specific store

## Native Messaging

Looks up host manifests in order:
1. `~/Library/Application Support/Nook/NativeMessagingHosts/`
2. Chrome, Chromium, Edge, Brave, Mozilla standard paths

Protocol: 4-byte native-endian length prefix + JSON. Supports single-shot (5s timeout) and long-lived `MessagePort` connections.

**Critical: Delegate method signatures** — The `WKWebExtensionControllerDelegate` native messaging methods have specific Swift names defined by `NS_SWIFT_NAME`. The parameter labels MUST match exactly:
```swift
// CORRECT — matches NS_SWIFT_NAME(webExtensionController(_:sendMessage:toApplicationWithIdentifier:for:replyHandler:))
func webExtensionController(_:, sendMessage:, toApplicationWithIdentifier applicationId: String?, for:, replyHandler:)

// WRONG — generates wrong ObjC selector, WebKit can't find it
func webExtensionController(_:, sendMessage:, to applicationId: String, for:, replyHandler:)
```
Similarly, `connectUsing` must use the completion handler form (not `async throws`) and the port type is `WKWebExtension.MessagePort` (Swift name for `WKWebExtensionMessagePort`).

**Unavailable host caching** — Extensions like Bitwarden poll `sendNativeMessage` every ~500ms. Failed host lookups are cached in `unavailableNativeHosts` and return `(["command": "disconnected"], nil)` immediately. Returning a non-nil reply with nil error prevents WebKit from logging "Runtime error" spam.

**Safari extension commands** — Safari `.appex` extensions send app-specific commands via native messaging instead of using web APIs. Common commands intercepted before the host lookup:
- `copyToClipboard` — writes `msg["text"]` to `NSPasteboard.general`
- `readFromClipboard` — reads from `NSPasteboard.general`
- `showPopover` — routes to `extensionContext.performAction(for:)`

## MV3 Worker Lifetime

Background service workers terminate after ~5 minutes idle. `wakeBackgroundWorkers()` is called from `notifyTabActivated` and from `ExtensionActionView` on `NSApplication.didBecomeActiveNotification`. Do not add polling timers to keep workers alive.

**Pending work** (`docs/superpowers/plans/2026-04-01-extension-tab-binding-fixes.md`): grant URL access on tab activation, guard tab notifications against nil webviews, remove popup double-load, fire URL/title property changes on tab switch. Partially applied in the working tree as of 2026-09.

## Delegate Methods (WKWebExtensionControllerDelegate)

Key delegate implementations in ExtensionManager:
- **Action popup**: Grants permissions, wakes MV3 service worker, positions popover via registered anchor views. Popup webview gets a JS clipboard polyfill via `PopupClipboardHandler` for extensions using web Clipboard APIs.
- **Native messaging**: Intercepts Safari-specific commands (`copyToClipboard`, `readFromClipboard`, `showPopover`) before forwarding to `NativeMessagingHandler`. Caches unavailable hosts.
- **Open tab/window**: Creates tabs for extension pages, handles OAuth popup flows
- **Options page**: Resolves URL from manifest (`options_ui.page` / `options_page`), opens in separate NSWindow with extension's webViewConfiguration. Includes path traversal protection.
- **Permission prompts**: `promptForPermissions()` and `promptForPermissionToAccess()` for runtime permission requests

## Clipboard in Extension Popups

WebContent processes are sandboxed and **cannot access the system pasteboard** (`CFPasteboardRef` fails with "Sandbox restriction"). This affects all clipboard operations in extension popups. Two complementary solutions:

1. **Native messaging interception** (`ExtensionManager+Delegate.swift`) — Safari-style extensions (e.g., Bitwarden) send clipboard commands via `browser.runtime.sendNativeMessage()`. The delegate intercepts `copyToClipboard`/`readFromClipboard` and writes to `NSPasteboard` from the app process.

2. **JS clipboard polyfill** (`PopupUIDelegate.swift`) — For extensions using web APIs (`navigator.clipboard.writeText`, `document.execCommand('copy')`). A `WKScriptMessageHandler` bridge routes clipboard writes through the app process.

**Key WKWebView gotcha**: `webView.configuration` returns a **copy** each time. Setting `preferences.setValue(...)` on it modifies a temporary. However, `userContentController` IS a shared reference — adding script message handlers through it works.

## Diagnostics

- `probeBackgroundHealth()` — Runs at +3s and +8s after background load; uses KVC to access `_backgroundWebView` and evaluates capability probe (available APIs, permissions, errors)
- `diagnoseExtensionState()` — Full diagnostic on content scripts + messaging per extension
- Memory debug logging uses `[MEMDEBUG]` prefix
