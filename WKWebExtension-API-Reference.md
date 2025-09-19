# WKWebExtension API Reference

Complete reference documentation for Apple's WKWebExtension framework (iOS 18.4+, macOS 15.4+).

## Core Classes

### WKWebExtension
An object that encapsulates a web extension's resources that the manifest file defines.

**Key Properties:**
- `displayName: String?` - The localized extension name
- `displayDescription: String?` - The localized extension description
- `version: String?` - The extension version
- `manifest: [String : Any]` - The parsed manifest as a dictionary
- `manifestVersion: Double` - The parsed manifest version
- `hasBackgroundContent: Bool` - Whether the extension has background content
- `hasInjectedContent: Bool` - Whether the extension has injectable content
- `hasOptionsPage: Bool` - Whether the extension has an options page
- `requestedPermissions: Set<WKWebExtension.Permission>` - Required permissions
- `optionalPermissions: Set<WKWebExtension.Permission>` - Optional permissions
- `requestedPermissionMatchPatterns: Set<WKWebExtension.MatchPattern>` - Required URL patterns
- `optionalPermissionMatchPatterns: Set<WKWebExtension.MatchPattern>` - Optional URL patterns

**Initializers:**
```swift
convenience init(appExtensionBundle: Bundle) async throws
convenience init(resourceBaseURL: URL) async throws
```

**Key Methods:**
- `icon(for: CGSize) -> UIImage?` - Returns extension icon for specified size
- `actionIcon(for: CGSize) -> UIImage?` - Returns action icon for specified size

---

### WKWebExtensionContext
An object that represents the runtime environment for a web extension.

**Key Properties:**
- `webExtension: WKWebExtension` - The extension this context represents
- `uniqueIdentifier: String` - Unique identifier for the extension
- `baseURL: URL` - Base URL for loading extension resources
- `isLoaded: Bool` - Whether context is loaded in an extension controller
- `commands: [WKWebExtension.Command]` - Commands associated with the extension
- `currentPermissions: Set<WKWebExtension.Permission>` - Currently granted permissions
- `currentPermissionMatchPatterns: Set<WKWebExtension.MatchPattern>` - Currently granted URL patterns
- `hasAccessToAllHosts: Bool` - Whether extension has access to all hosts
- `hasAccessToAllURLs: Bool` - Whether extension has access to all URLs
- `openWindows: [any WKWebExtensionWindow]` - Open windows exposed to extension
- `openTabs: Set<AnyHashable>` - Open tabs exposed to extension
- `focusedWindow: (any WKWebExtensionWindow)?` - Currently focused window

**Key Methods:**
- `action(for: (any WKWebExtensionTab)?) -> WKWebExtension.Action?` - Get action for tab
- `performAction(for: (any WKWebExtensionTab)?)` - **Trigger action (popup presentation)**
- `hasPermission(WKWebExtension.Permission) -> Bool` - Check permission status
- `hasAccess(to: URL) -> Bool` - Check URL access
- `setPermissionStatus(_:for:)` - Set permission status

---

### WKWebExtensionController
An object that manages a set of loaded extension contexts.

**Key Properties:**
- `configuration: WKWebExtensionController.Configuration` - Controller configuration
- `delegate: (any WKWebExtensionControllerDelegate)?` - **Controller delegate**
- `extensionContexts: Set<WKWebExtensionContext>` - Loaded extension contexts
- `extensions: Set<WKWebExtension>` - Loaded extensions

**Key Methods:**
- `load(WKWebExtensionContext) throws` - Load extension context
- `unload(WKWebExtensionContext) throws` - Unload extension context
- `extensionContext(for: WKWebExtension) -> WKWebExtensionContext?` - Get context for extension

---

### WKWebExtension.Action
An object that encapsulates the properties for an individual web extension action.

**Key Properties:**
- `associatedTab: (any WKWebExtensionTab)?` - Associated tab or nil for default
- `label: String` - Localized display label
- `isEnabled: Bool` - Whether action is enabled
- `presentsPopup: Bool` - Whether action has a popup
- `popupWebView: WKWebView?` - Web view loaded with popup page
- `popupViewController: UIViewController?` - View controller for popup (iOS)
- `popupPopover: NSPopover?` - **Popover for popup presentation (macOS)**
- `webExtensionContext: WKWebExtensionContext?` - Related extension context

**Key Methods:**
- `icon(for: CGSize) -> UIImage?` - Get action icon for size
- `closePopup()` - Trigger popup dismissal

---

## Delegate Protocol

### WKWebExtensionControllerDelegate
**Critical delegate method for popup handling:**

```swift
func webExtensionController(
    _ controller: WKWebExtensionController,
    presentActionPopup action: WKWebExtension.Action,
    for extensionContext: WKWebExtensionContext,
    completionHandler: @escaping (Error?) -> Void
)
```

**Other important delegate methods:**
- `openNewTabUsing(_:for:completionHandler:)` - Handle new tab requests
- `openNewWindowUsing(_:for:completionHandler:)` - Handle new window requests  
- `promptForPermissions(_:in:for:completionHandler:)` - Handle permission requests
- `focusedWindowFor(_:)` - Return focused window
- `openWindowsFor(_:)` - Return open windows list

---

## Key Protocols

### WKWebExtensionTab
Protocol representing a tab to web extensions.

**Key Methods:**
- `url(for:) -> URL?` - Get tab URL
- `title(for:) -> String?` - Get tab title
- `isSelected(for:) -> Bool` - Check if tab is selected
- `activate(for:completionHandler:)` - Activate the tab
- `close(for:completionHandler:)` - Close the tab

### WKWebExtensionWindow
Protocol representing a window to web extensions.

**Key Methods:**
- `activeTab(for:) -> (any WKWebExtensionTab)?` - Get active tab
- `tabs(for:) -> [any WKWebExtensionTab]` - Get all tabs
- `frame(for:) -> CGRect` - Get window frame
- `focus(for:completionHandler:)` - Focus the window

---

## Permissions & Match Patterns

### WKWebExtension.Permission
**Common permissions:**
- `.activeTab` - Access to active tab only
- `.tabs` - Access to tabs API
- `.storage` - Access to storage APIs
- `.scripting` - Access to scripting APIs
- `.contextMenus` / `.menus` - Context menu access
- `.declarativeNetRequest` - Content blocking rules
- `.cookies` - Cookie access
- `.webNavigation` - Navigation events
- `.nativeMessaging` - Communication with app

### WKWebExtension.MatchPattern
Represents URL patterns for host permissions.

**Common patterns:**
- `<all_urls>` - Access to all URLs
- `*://*/*` - All hosts and schemes  
- `https://*.example.com/*` - Specific domain pattern

### WKWebExtensionContext.PermissionStatus
Permission status values used with `setPermissionStatus(_:for:)`.

- `unknown` – Status not yet determined
- `requestedExplicitly` / `requestedImplicitly` – Permission has been requested
- `grantedExplicitly` / `grantedImplicitly` – Permission granted (explicit = by user)
- `deniedExplicitly` / `deniedImplicitly` – Permission denied (explicit = by user)

Use explicit variants when applying a user’s choice from your own UI or the controller delegate. For example: grant → `grantedExplicitly`, deny → `deniedExplicitly`.

---

## Data Types & Storage

### WKWebExtension.DataType
Storage types for extension data:
- `.local` - Local storage (browser.storage.local)
- `.session` - Session storage (browser.storage.session)  
- `.synchronized` - Sync storage (browser.storage.sync)

---

## Error Handling

### WKWebExtension.Error
Common error codes:
- `.invalidManifest` - Invalid manifest.json
- `.invalidManifestEntry` - Invalid manifest entry
- `.resourceNotFound` - Resource not found
- `.unsupportedManifestVersion` - Unsupported manifest version
- `.invalidArchive` - Invalid ZIP archive

---

## Configuration

### WKWebExtensionController.Configuration
- `.default()` - Default persistent configuration
- `.nonPersistent()` - Non-persistent configuration
- `init(identifier: UUID)` - Persistent with unique ID

**Properties:**
- `isPersistent: Bool` - Whether data persists to filesystem
- `identifier: UUID?` - Unique identifier for persistent storage
- `defaultWebsiteDataStore: WKWebsiteDataStore!` - Data store for website data
- `webViewConfiguration: WKWebViewConfiguration!` - Base web view configuration

---

## Implementation Pattern

**Proper popup handling flow:**
1. Extension button clicked → call `extensionContext.performAction(for: nil)`
2. System calls delegate method `presentActionPopup(_:for:completionHandler:)`
3. Delegate accesses `action.popupPopover` and presents it
4. Call completion handler with success/error

**Example:**
```swift
// In button action
// Pass the active tab when available for better context
let associatedTab: (any WKWebExtensionTab)? = currentTabAdapter // or nil
extensionContext.performAction(for: associatedTab)

// In delegate method
func webExtensionController(_ controller: WKWebExtensionController, 
                          presentActionPopup action: WKWebExtension.Action, 
                          for extensionContext: WKWebExtensionContext, 
                          completionHandler: @escaping (Error?) -> Void) {
    if let popover = action.popupPopover {
        popover.show(relativeTo: buttonRect, of: contentView, preferredEdge: .minY)
        completionHandler(nil)
    }
}
```

**Associate app web views with the controller:**

To enable content script injection and tabs/windows APIs for your app’s own `WKWebView` instances, associate your `WKWebViewConfiguration` with the controller before creating any web views:

```swift
// Prefer a persistent configuration with a stable identifier
let uuid = UUID(uuidString: UserDefaults.standard.string(forKey: "Pulse.WKWebExtensionController.Identifier") ?? "") ?? UUID()
UserDefaults.standard.set(uuid.uuidString, forKey: "Pulse.WKWebExtensionController.Identifier")
let controller = WKWebExtensionController(configuration: .init(identifier: uuid))
controller.configuration.webViewConfiguration = sharedWebViewConfig
sharedWebViewConfig.webExtensionController = controller
```

Ensure this is done early (e.g., app startup) before any `WKWebView` is created, otherwise those web views won’t receive content scripts.

**Notify tab/window events and property changes:**

Apps should keep the controller informed about browser state so extensions get consistent `tabs.*` events and data.

```swift
// When a window opens/focuses
controller.didOpenWindow(windowAdapter)
controller.didFocusWindow(windowAdapter)

// When tabs open/activate/close
controller.didOpenTab(tabAdapter)
controller.didActivateTab(tabAdapter, previousActiveTab: previousAdapter)
controller.didSelectTabs([tabAdapter])
controller.didDeselectTabs([previousAdapter])
controller.didCloseTab(tabAdapter, windowIsClosing: false)

// When tab properties change (e.g., URL or title)
controller.didChangeTabProperties([.URL, .title], for: tabAdapter)
```

---

*Reference based on Apple's WKWebExtension documentation for macOS 15.4+ and iOS 18.4+*

---

## Execution Worlds (MAIN vs ISOLATED)

WKWebExtension maps Chrome’s execution “worlds” to WebKit content worlds. This matters for extensions like Dark Reader that must inject some logic into the page’s own JavaScript context.

- World semantics:
  - `ISOLATED` → Injects into WebKit’s isolated extension world (`WKContentWorld.defaultClient` or a private, per‑extension world). Extension APIs are available here. This is the default.
  - `MAIN` → Injects into the page’s main world (`WKContentWorld.page`). Extension APIs are NOT available here by design.

- Availability:
  - Apple added support for the `world` option (Chrome MV3) in WebKit after macOS 15.4. Use macOS 15.5+ (and the corresponding Safari/WebKit) to rely on it. Earlier builds ignore `world` and run in the isolated world.

- How Pulse enables this:
  - We associate our `WKWebViewConfiguration` with the `WKWebExtensionController` early so the engine can honor world selection for our app web views. See “Associate app web views with the controller” above.
  - We grant `.scripting` permission when requested so `chrome.scripting.*` works.
  - We notify the controller of windows/tabs so targets exist for injections.

### Using worlds with chrome.scripting

Example: inject a small probe into MAIN vs ISOLATED and report where it executed.

```js
// Requires "permissions": ["scripting"], and a valid tabId
async function probeWorld(tabId, world) {
  const [{ result }] = await chrome.scripting.executeScript({
    target: { tabId },
    world, // 'MAIN' or 'ISOLATED'
    func: () => ({
      hasExtensionAPIs: typeof browser !== 'undefined' || typeof chrome !== 'undefined',
      worldHint: typeof browser === 'undefined' && typeof chrome === 'undefined' ? 'MAIN' : 'ISOLATED'
    })
  });
  return result;
}
```

Expected behavior on macOS 15.5+:
- `world: 'ISOLATED'` → `hasExtensionAPIs === true` and `worldHint === 'ISOLATED'`.
- `world: 'MAIN'` → `hasExtensionAPIs === false` and `worldHint === 'MAIN'`.

### Content scripts with world

Manifest V3 supports `world` on `content_scripts` entries. On macOS 15.5+ WebKit, entries with `"world": "MAIN"` are injected into the page world; entries without it (or `"ISOLATED"`) go into an isolated world.

```json
{
  "manifest_version": 3,
  "name": "World Demo",
  "version": "1.0",
  "permissions": ["scripting"],
  "host_permissions": ["<all_urls>"],
  "content_scripts": [
    {
      "matches": ["<all_urls>"],
      "js": ["main-world.js"],
      "run_at": "document_start",
      "world": "MAIN"
    },
    {
      "matches": ["<all_urls>"],
      "js": ["isolated-world.js"],
      "run_at": "document_end",
      "world": "ISOLATED"
    }
  ]
}
```

Notes:
- Code injected into `MAIN` must not call extension APIs. Communicate with the extension via `window.postMessage` or DOM signals if needed.
- If running on macOS 15.4 (or earlier WebKit), `world` may be ignored and everything runs in the isolated world.

### Fallbacks when world is missing

If you must support an OS/WebKit build that doesn’t honor `world`:
- Prefer `ISOLATED` and avoid patterns that require page‑world prototype patching.
- For specific extensions (e.g., Dark Reader) that only need a small bridge in the page world, inject a minimal host‑side `WKUserScript` into `WKContentWorld.page` that relays DOM events or `postMessage` signals to the isolated script. Keep this lightweight and avoid re‑implementing full extension logic.
- Consider raising the minimum OS for “page‑world required” extensions to macOS 15.5+ where possible.

### Checklist in Pulse
- Web view association: `configuration.webExtensionController = controller` before creating web views.
- Permissions: ensure `.scripting` and required host permissions are granted.
- Tab/window plumbing: call `didOpenWindow`, `didOpenTab`, `didActivateTab`, etc., so `tabId` targets resolve.
- OS gating: prefer macOS 15.5+ when extensions rely on `world: 'MAIN'`.

This aligns with Apple’s WKWebExtension docs and the internal mapping to `WKContentWorld.page`/`defaultClient`.
