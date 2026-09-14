# Extension System (WKWebExtension)

Deep documentation for Nook's web extension subsystem. For project-level context, see the [root CLAUDE.md](../../../CLAUDE.md).

## Availability

Deployment target is macOS 26.0, so WKWebExtension (15.4+) and content scripts (15.5+) are always available. No `@available` / `#available` guards are needed or wanted in extension code.

## Key Files

| File | Purpose |
|------|---------|
| `ExtensionManager.swift` | Core facade: properties, controller setup, context identity, `attach(browserManager:)` |
| `ExtensionManager+Installation.swift` | Install/update pipeline with consent sheet, stable IDs, `registerContext`, persistence, Safari discovery, enable/disable/uninstall |
| `ExtensionManager+Updates.swift` | Daily store update check for Web Store / Edge installs (on load and app activation, no timer) |
| `ExtensionManager+Delegate.swift` | All `WKWebExtensionControllerDelegate` methods: popup, permissions, tabs/windows, options page, native messaging |
| `ExtensionManager+ExternallyConnectable.swift` | `externally_connectable` polyfill and bridge content scripts, manifest patching for WebKit |
| `ExtensionManager+Diagnostics.swift` | Debug-only background health probes and per-navigation state diagnosis |
| `ExtensionManager+TabNotifications.swift` | Tab adapters, lifecycle notifications (opened tabs only), scoped URL grants, action anchors |
| `NativeMessagingHandler.swift` | Host manifest lookup with `allowed_origins` enforcement, host process I/O, single-shot and port modes |
| `BitwardenBiometricHandler.swift` | In-process host for Bitwarden's `.appex` `connectNative("com.8bit.bitwarden")` biometric unlock: prompts Touch ID (LocalAuthentication) and returns the symmetric key from the `Bitwarden_biometric` Keychain service, so no Bitwarden desktop app is required |
| `InternalNativePortHandler.swift` | Small protocol for in-process native message port handlers |
| `PopupUIDelegate.swift` | `PopupClipboardHandler` (JS↔native clipboard bridge via WKScriptMessageHandler) + `PopupUIDelegate` (WKUIDelegate for popup webviews) |
| `ExtensionBridge.swift` | `WKWebExtensionTab` / `WKWebExtensionWindow` protocol adapters |
| `Nook/Models/Extension/ExtensionModels.swift` | `ExtensionEntity` (SwiftData) + `InstalledExtension` runtime model |
| `Nook/Models/BrowserConfig/BrowserConfig.swift` | Shared `WKWebViewConfiguration` factory — extension controller lives here |
| `Nook/Components/Extensions/ExtensionActionView.swift` | Toolbar buttons, popup anchor positioning |
| `Nook/Components/Extensions/ExtensionPermissionView.swift` | Permission grant/deny dialogs |
| `Nook/Components/Extensions/PopupConsoleWindow.swift` | Debug console for extension popups |
| `Nook/Utils/ExtensionUtils.swift` | Manifest validation, `ExtensionError` |
| `Nook/Utils/WebStoreDownloader.swift` | `ExtensionStore` (chrome/edge), CRX download, update-check protocol |
| `Nook/Utils/WebStoreScriptHandler.swift` | "Add to Nook" handler; isolated content world, store-origin checks |

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

Supported formats: `.zip`, `.appex` (Safari extension bundle), `.app` (scans `Contents/PlugIns/` for `.appex`), bare directories. Every path (file picker, Safari discovery, Web Store, automatic update) goes through `installExtension(from:store:extensionId:interactive:)`.

1. Stage in `Extensions/temp_<uuid>` (deleted on any failure). Packages containing symbolic links are rejected.
2. `ExtensionUtils.validateManifest()`, MV3 service-worker check, `patchManifestForWebKit()`.
3. **ID**: caller-supplied stable ID (store ID, Safari bundle identifier), else the Chrome ID derived from the manifest `key` (SHA-256, first 16 bytes, hex mapped to a-p), else a random UUID. Installs made before September 2026 have UUID IDs.
4. Same ID already installed: same version is rejected, a different version is an **in-place update** (entity kept, so enabled state, optional grants, and storage under the same `uniqueIdentifier` survive). A UUID-ID copy with the same name is replaced when a stable-ID install arrives.
5. **Consent**: `ExtensionPermissionView` sheet for every fresh install, and for updates only when the new version adds permissions or hosts. Background updates (`interactive: false`) that need consent are skipped.
6. Swap into `~/Library/Application Support/Nook/Extensions/{extensionId}/`, save `ExtensionEntity` (`sourceStore` set for store installs), then `registerContext(for:webExtension:)`.

`registerContext` is the single place a context is created: identity, required permissions and patterns, restored optional grants, externally_connectable bridge, `load`, background start, URL grants for already-open tabs.

## Chrome Web Store

`WebStoreInjector.js` and the `nookWebStore` handler are added only after a navigation to an exact `https` store host, and both live in the `NookWebStore` content world, so page scripts cannot reach the handler. The handler also requires main frame, store origin, and an a-p ID; clicks must be `isTrusted`. The native consent sheet is the final gate.

## Externally Connectable Bridge

**Problem**: Pages like `account.proton.me` call `browser.runtime.sendMessage(SAFARI_EXT_ID, msg)` but Safari extension IDs don't match WKWebExtension IDs.

**Solution**: `patchManifestForWebKit(at:extensionId:)` adds two content scripts to the extension's own manifest, matching its sane `externally_connectable` patterns (wildcard-only and TLD-wide hosts are dropped):
- **`nook_ec_polyfill.js`** (`"world": "MAIN"`): wraps the page's `chrome.runtime` / `browser.runtime` `sendMessage` and `connect`, relays via `window.postMessage`. The extension ID is baked in at patch time.
- **`nook_bridge.js`** (ISOLATED): receives those messages, calls the real `runtime.sendMessage` / `connect`, posts responses back.

Because they are the extension's content scripts, WebKit handles injection into every tab and window, skips private tabs, and stops injecting on disable or uninstall. There is no Nook user script in the shared configuration.

Verified in a standalone `WKWebExtensionController` harness (MV2 and MV3): MAIN-world content scripts run, reach the isolated world by `postMessage`, and the shipped polyfill plus bridge deliver both `chrome.runtime.sendMessage(id, msg, callback)` and `browser.runtime.sendMessage(id, msg)` to the background and back. The harness only works after `didOpenTab` for the webview; WebKit drops content-script messages from unregistered tabs.

Trust: the background sees these on `runtime.onMessage` as if from its own content script, not `onMessageExternal`, so any script on a listed origin can send them.

## Extension Bridge (ExtensionBridge.swift)

- **`ExtensionWindowAdapter`** implements `WKWebExtensionWindow`: exposes active tab, tab list, window state (minimized/maximized/fullscreen), focus/close operations, privacy status.
- **`ExtensionTabAdapter`** implements `WKWebExtensionTab`: exposes url, title, selection state, loading, pinned, muted, audio state. Returns `tab.assignedWebView` (does NOT trigger lazy init). Stable adapters cached in `tabAdapters` dictionary by `Tab.id`.

## Tab <> Extension Notification

Tab notifies the extension system after webview creation:
```
Tab.setupWebView()
  -> ExtensionManager.shared.notifyTabOpened(tab)  // controller.didOpenTab(adapter), records openedTabIDs
  -> If active: notifyTabActivated()                // controller.didActivateTab(adapter)
  -> tab.didNotifyOpenToExtensions = true
```

Activation, property-change, and close events are forwarded only for tabs in `openedTabIDs`. Private tabs are never opened: `stableAdapter(for:)` returns nil for them.

## Permission Model

- **Install/update**: user approves required `permissions` and host patterns in the consent sheet; `registerContext` grants exactly those on every load. Optional permissions and hosts are never granted up front.
- **Runtime** (`chrome.permissions.request`, URL access prompts): `ExtensionPermissionView` via the delegate; approvals are persisted to `ExtensionEntity.grantedOptional*` and restored on load.
- **Site access**: WebKit grants implicit access for URLs covered by granted patterns (verified: `permissionStatus(for:)` returns `grantedImplicitly`). `grantExtensionAccessToURL` only adds an explicit grant when a granted pattern covers the URL but WebKit did not report access (earlier code reported this for IP-address hosts). It never grants outside an extension's patterns. Opening a popup grants nothing; `activeTab` comes from WebKit on the click gesture.
- **Clipboard over native messaging** (`copyToClipboard` / `readFromClipboard`): requires `clipboardWrite` / `clipboardRead` in the manifest `permissions`. WebKit has no `clipboardRead` constant, so the manifest is read directly.

## Scope and Storage

- Extensions are **global**: one controller, one install and enabled state, one storage namespace for all profiles. `WKWebExtensionController.configuration` returns a copy, so the data store cannot be swapped per profile after init; there is no per-profile switching.
- Extension pages use `WKWebsiteDataStore(forIdentifier: controllerIdentifier)`. `chrome.storage` is keyed by context `uniqueIdentifier` under the controller identifier.
- **Private (ephemeral) profiles get no controller** (`BrowserConfiguration.webViewConfiguration(for:)` and `Tab.setupWebView`), so no content scripts, no tab visibility, no events. `ExtensionWindowAdapter.isPrivate` is always false.
- One `ExtensionWindowAdapter` represents all windows. `tabs.query` sees every non-private tab across spaces; the active tab is the focused window's current tab (`BrowserManager.setActiveWindowState` notifies extensions on window focus). With a private window focused there is no active tab. Per-window adapters are deliberately not implemented: Nook spaces are shared across windows and the same tab can show in several, which has no Chrome equivalent.

## Native Messaging

Looks up host manifests in order:
1. `~/Library/Application Support/Nook/NativeMessagingHosts/`
2. Chrome, Chromium, Edge, Brave, Mozilla standard paths (user, then system)

A manifest is used only if `name` equals the host name, `type` is stdio, `path` is absolute, the binary is executable under an allowed prefix, and the caller is allowed: `allowed_origins` contains `chrome-extension://<id>/` (store and key-derived IDs only) or `nook-extension://<id>/`, or Firefox `allowed_extensions` contains the manifest's gecko ID. Extensions with UUID IDs cannot reach third-party hosts; reinstall from the store to get a Chrome ID.

Protocol: 4-byte native-endian length prefix + JSON, 1 MB cap. Single-shot mode (5 s timeout) and long-lived ports. All callbacks into WebKit run on the main thread; port handlers stay retained in `nativeMessagingHandlers` until the port disconnects or the host exits.

**Message port handler signature**: `messageHandler` is `(message, error)`. Code before September 2026 read the error slot as the message, so in-process port handlers (Bitwarden biometrics) never received messages.

**Critical: Delegate method signatures** — The `WKWebExtensionControllerDelegate` native messaging methods have specific Swift names defined by `NS_SWIFT_NAME`. The parameter labels MUST match exactly:
```swift
// CORRECT — matches NS_SWIFT_NAME(webExtensionController(_:sendMessage:toApplicationWithIdentifier:for:replyHandler:))
func webExtensionController(_:, sendMessage:, toApplicationWithIdentifier applicationId: String?, for:, replyHandler:)

// WRONG — generates wrong ObjC selector, WebKit can't find it
func webExtensionController(_:, sendMessage:, to applicationId: String, for:, replyHandler:)
```
Similarly, `connectUsing` must use the completion handler form (not `async throws`) and the port type is `WKWebExtension.MessagePort` (Swift name for `WKWebExtensionMessagePort`).

**Unavailable host caching** — Extensions like Bitwarden poll `sendNativeMessage` every ~500ms. Missing or disallowed hosts are cached per extension+host in `unavailableNativeHosts` (timeouts are not cached) and return `(["command": "disconnected"], nil)` immediately. Ports to such hosts fall back to in-process handling (`InternalNativePortHandler`, then clipboard/popover commands).

**Safari extension commands** — intercepted before the host lookup: `copyToClipboard`, `readFromClipboard` (both permission-gated, see Permission Model), `showPopover` (routes to `extensionContext.performAction(for:)`), `sleep` (30 s long-poll reply).

## MV3 Worker Lifetime

Background service workers terminate after ~5 minutes idle. `wakeBackgroundWorkers()` is called from `notifyTabActivated` and from `ExtensionActionView` on `NSApplication.didBecomeActiveNotification`. Do not add polling timers to keep workers alive.

The April 2026 tab-binding plan (`docs/superpowers/plans/2026-04-01-extension-tab-binding-fixes.md`) is fully applied.

## Delegate Methods (WKWebExtensionControllerDelegate)

Key delegate implementations in ExtensionManager:
- **Action popup**: Wakes MV3 service worker (in `ExtensionActionView`), positions popover via registered anchor views. Grants no permissions and never reloads the popup: WebKit calls the delegate after the popup has loaded, in a fresh webview each open. Popup webview gets a JS clipboard polyfill via `PopupClipboardHandler` for extensions using web Clipboard APIs.
- **Native messaging**: Intercepts Safari-specific commands before forwarding to `NativeMessagingHandler`. Caches unavailable hosts per extension.
- **Open tab/window**: Creates tabs for extension pages, handles OAuth popup flows
- **Options page**: Resolves URL from manifest (`options_ui.page` / `options_page`), opens in separate NSWindow with extension's webViewConfiguration. Includes path traversal protection.
- **Permission prompts**: `promptForPermissions()` and `promptForPermissionToAccess()` for runtime permission requests

## Clipboard in Extension Popups

WebContent processes are sandboxed and **cannot access the system pasteboard** (`CFPasteboardRef` fails with "Sandbox restriction"). This affects all clipboard operations in extension popups. Two complementary solutions:

1. **Native messaging interception** (`ExtensionManager+Delegate.swift`) — Safari-style extensions (e.g., Bitwarden) send clipboard commands via `browser.runtime.sendNativeMessage()`. The delegate intercepts `copyToClipboard`/`readFromClipboard` and writes to `NSPasteboard` from the app process.

2. **JS clipboard polyfill** (`PopupUIDelegate.swift`) — For extensions using web APIs (`navigator.clipboard.writeText`, `document.execCommand('copy')`). A `WKScriptMessageHandler` bridge routes clipboard writes through the app process.

**Key WKWebView gotcha**: `webView.configuration` returns a **copy** each time. Setting `preferences.setValue(...)` on it modifies a temporary. However, `userContentController` IS a shared reference — adding script message handlers through it works.

## Diagnostics

Debug builds only (`#if DEBUG`):
- `probeBackgroundHealth()` — Runs at +3s and +8s after background load; reads the private `_backgroundWebView` only after a `responds(to:)` check (plain KVC on a renamed key raises) and evaluates a capability probe.
- `diagnoseExtensionState()` — Per navigation: content script and messaging state per extension, including `urlAccess` (`WKWebExtensionContext.PermissionStatus` raw value: 2 implicit grant, 3 explicit grant, 0 unknown).

