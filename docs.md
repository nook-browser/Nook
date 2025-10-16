WKWebExtension
An object that encapsulates a web extension’s resources that the manifest file defines.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
@MainActor
class WKWebExtension
Overview
This class reads and parses the manifest.json file along with the supporting resources like icons and
localizations.

Topics
Classes
class Action
An object that encapsulates the properties for an individual web extension action.
class Command
An object that encapsulates the properties for an individual web extension command.
class DataRecord
An object that represents a record of stored data for a specific web extension context.
class MatchPattern
An object that represents a way to specify groups of URLs.
class MessagePort
An object that manages message-based communication with a web extension.
class TabConfiguration
An object that encapsulates configuration options for a tab in an extension.
class WindowConfiguration
An object that encapsulates configuration options for a window in an extension.
class Configuration
A WKWebExtensionController.Configuration object with which to initialize a web extension controller.
Structures
struct DataType
Constants for specifying data types for a WKWebExtension.DataRecord.
struct Error
Constants that indicate errors in the WKWebExtension domain.
struct Permission
Constants for specifying permission in a WKWebExtensionContext.
struct TabChangedProperties
Constants the web extension controller and web extension context use to indicate tab changes.
Enumerations
enum WindowState
Constants used by WKWebExtensionWindow to indicate possible states of a window.
enum WindowType
Constants used by WKWebExtensionWindow to indicate the type of a window.
Initializers
convenience init(appExtensionBundle: Bundle) async throws
Creates a web extension initialized with a specified app extension bundle.
convenience init(resourceBaseURL: URL) async throws
Creates a web extension initialized with a specified resource base URL, which can point to either a directory or a
ZIP archive.
Instance Properties
var allRequestedMatchPatterns: Set<WKWebExtension.MatchPattern>
The set of websites that the extension requires access to for injected content and for receiving messages from
websites.
var defaultLocale: Locale?
The default locale for the extension.
var displayActionLabel: String?
The default localized extension action label.
var displayDescription: String?
The localized extension description.
var displayName: String?
The localized extension name.
var displayShortName: String?
The localized extension short name.
var displayVersion: String?
The localized extension display version.
var errors: [any Error]
An array of all errors that occurred during the processing of the extension.
var hasBackgroundContent: Bool
A Boolean value indicating whether the extension has background content that can run when needed.
var hasCommands: Bool
A Boolean value indicating whether the extension includes commands that users can invoke.
var hasContentModificationRules: Bool
A Boolean value indicating whether the extension includes rules used for content modification or blocking.
var hasInjectedContent: Bool
A Boolean value indicating whether the extension has script or stylesheet content that can be injected into
webpages.
var hasOptionsPage: Bool
A Boolean value indicating whether the extension has an options page.
var hasOverrideNewTabPage: Bool
A Boolean value indicating whether the extension provides an alternative to the default new tab page.
var hasPersistentBackgroundContent: Bool
A Boolean value indicating whether the extension has background content that stays in memory as long as the
extension is loaded.
var manifest: [String : Any]
The parsed manifest as a dictionary.
var manifestVersion: Double
The parsed manifest version, or 0 if there is no version specified in the manifest.
var optionalPermissionMatchPatterns: Set<WKWebExtension.MatchPattern>
The set of websites that the extension may need access to for optional functionality.
var optionalPermissions: Set<WKWebExtension.Permission>
The set of permissions that the extension may need for optional functionality.
var requestedPermissionMatchPatterns: Set<WKWebExtension.MatchPattern>
The set of websites that the extension requires access to for its base functionality.
var requestedPermissions: Set<WKWebExtension.Permission>
The set of permissions that the extension requires for its base functionality.
var version: String?
The extension version.
Instance Methods
func actionIcon(for: CGSize) -> UIImage?
Returns the default action icon for the specified size.
func icon(for: CGSize) -> UIImage?
Returns the extension’s icon image for the specified size.
func supportsManifestVersion(Double) -> Bool
Checks if a manifest version is supported by the extension.
Relationships
Inherits From
NSObject
Conforms To
CVarArg
CustomDebugStringConvertible
CustomStringConvertible
Equatable
Hashable
NSObjectProtocol
Sendable
See Also
Web extensions
protocol WKWebExtensionTab
A protocol with methods that represent a tab to web extensions.
protocol WKWebExtensionWindow
A protocol with methods that represent a window to web extensions.
class WKWebExtensionContext
An object that represents the runtime environment for a web extension.
class WKWebExtensionController
An object that manages a set of loaded extension contexts.
protocol WKWebExtensionControllerDelegate
A group of methods you use to customize web extension interactions.

WKWebExtensionTab
A protocol with methods that represent a tab to web extensions.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
@MainActor
protocol WKWebExtensionTab : NSObjectProtocol
Topics
Instance Methods
func activate(for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to activate the tab, making it frontmost.
func close(for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to close the tab.
func detectWebpageLocale(for: WKWebExtensionContext, completionHandler: (Locale?, (any Error)?) -> Void)
Called to detect the locale of the webpage currently loaded in the tab.
func duplicate(using: WKWebExtension.TabConfiguration, for: WKWebExtensionContext, completionHandler: ((any
WKWebExtensionTab)?, (any Error)?) -> Void)
Called to duplicate the tab.
func goBack(for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to navigate the tab to the previous page in its history.
func goForward(for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to navigate the tab to the next page in its history.
func indexInWindow(for: WKWebExtensionContext) -> Int
Called when the index of the tab in the window is needed.
func isLoadingComplete(for: WKWebExtensionContext) -> Bool
Called to check if the tab has finished loading.
func isMuted(for: WKWebExtensionContext) -> Bool
Called to check if the tab is currently muted.
func isPinned(for: WKWebExtensionContext) -> Bool
Called when the pinned state of the tab is needed.
func isPlayingAudio(for: WKWebExtensionContext) -> Bool
Called to check if the tab is currently playing audio.
func isReaderModeActive(for: WKWebExtensionContext) -> Bool
Called to check if the tab is currently showing reader mode.
func isReaderModeAvailable(for: WKWebExtensionContext) -> Bool
Called to check if reader mode is available for the tab.
func isSelected(for: WKWebExtensionContext) -> Bool
Called when the selected state of the tab is needed.
func loadURL(URL, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to load a URL in the tab.
func parentTab(for: WKWebExtensionContext) -> (any WKWebExtensionTab)?
Called when the parent tab for the tab is needed.
func pendingURL(for: WKWebExtensionContext) -> URL?
Called when the pending URL of the tab is needed.
func reload(fromOrigin: Bool, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to reload the current page in the tab.
func setMuted(Bool, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to set the mute state of the tab.
func setParentTab((any WKWebExtensionTab)?, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to set or clear the parent tab for the tab.
func setPinned(Bool, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to set the pinned state of the tab.
func setReaderModeActive(Bool, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to set the reader mode for the tab.
func setSelected(Bool, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to set the selected state of the tab.
func setZoomFactor(Double, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to set the zoom factor of the tab.
func shouldBypassPermissions(for: WKWebExtensionContext) -> Bool
Called to determine if the tab should bypass host permission checks.
func shouldGrantPermissionsOnUserGesture(for: WKWebExtensionContext) -> Bool
Called to determine if permissions should be granted for the tab on user gesture.
func size(for: WKWebExtensionContext) -> CGSize
Called when the size of the tab is needed.
func takeSnapshot(using: WKSnapshotConfiguration, for: WKWebExtensionContext, completionHandler: (UIImage?, (any
Error)?) -> Void)
Called to capture a snapshot of the current webpage as an image.
func title(for: WKWebExtensionContext) -> String?
Called when the title of the tab is needed.
func url(for: WKWebExtensionContext) -> URL?
Called when the URL of the tab is needed.
func webView(for: WKWebExtensionContext) -> WKWebView?
Called when the web view for the tab is needed.
func window(for: WKWebExtensionContext) -> (any WKWebExtensionWindow)?
Called when the window containing the tab is needed.
func zoomFactor(for: WKWebExtensionContext) -> Double
Called when the zoom factor of the tab is needed.
Relationships
Inherits From
NSObjectProtocol
See Also
Web extensions
class WKWebExtension
An object that encapsulates a web extension’s resources that the manifest file defines.
protocol WKWebExtensionWindow
A protocol with methods that represent a window to web extensions.
class WKWebExtensionContext
An object that represents the runtime environment for a web extension.
class WKWebExtensionController
An object that manages a set of loaded extension contexts.
protocol WKWebExtensionControllerDelegate
A group of methods you use to customize web extension interactions.

WKWebExtensionWindow
A protocol with methods that represent a window to web extensions.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
@MainActor
protocol WKWebExtensionWindow : NSObjectProtocol
Topics
Instance Methods
func activeTab(for: WKWebExtensionContext) -> (any WKWebExtensionTab)?
Called when the active tab is needed for the window.
func close(for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to close the window.
func focus(for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to focus the window.
func frame(for: WKWebExtensionContext) -> CGRect
Called when the frame of the window is needed.
func isPrivate(for: WKWebExtensionContext) -> Bool
Called when the private state of the window is needed.
func screenFrame(for: WKWebExtensionContext) -> CGRect
Called when the screen frame containing the window is needed.
func setFrame(CGRect, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to set the frame of the window.
func setWindowState(WKWebExtension.WindowState, for: WKWebExtensionContext, completionHandler: ((any Error)?) ->
Void)
Called to set the state of the window.
func tabs(for: WKWebExtensionContext) -> [any WKWebExtensionTab]
Called when the tabs are needed for the window.
func windowState(for: WKWebExtensionContext) -> WKWebExtension.WindowState
Called when the state of the window is needed.
func windowType(for: WKWebExtensionContext) -> WKWebExtension.WindowType
Called when the type of the window is needed.
Relationships
Inherits From
NSObjectProtocol
See Also
Web extensions
class WKWebExtension
An object that encapsulates a web extension’s resources that the manifest file defines.
protocol WKWebExtensionTab
A protocol with methods that represent a tab to web extensions.
class WKWebExtensionContext
An object that represents the runtime environment for a web extension.
class WKWebExtensionController
An object that manages a set of loaded extension contexts.
protocol WKWebExtensionControllerDelegate
A group of methods you use to customize web extension interactions.

WKWebExtensionContext
An object that represents the runtime environment for a web extension.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
@MainActor
class WKWebExtensionContext
Overview
This class provides methods for managing the extension’s permissions, allowing it to inject content, run background
 logic, show popovers, and display other web-based UI to the user.

Topics
Enumerations
enum PermissionStatus
Constants used to indicate permission status in web extension context.
Structures
struct Error
Constants used to indicate errors in the web extension context domain.
struct NotificationUserInfoKey
Constants for specifying web extension context information in notifications.
Initializers
init(for: WKWebExtension)
Returns a web extension context initialized with a specified extension.
Instance Properties
var baseURL: URL
The base URL the context uses for loading extension resources or injecting content into webpages.
var commands: [WKWebExtension.Command]
The commands associated with the extension.
var currentPermissionMatchPatterns: Set<WKWebExtension.MatchPattern>
The currently granted permission match patterns that have not expired.
var currentPermissions: Set<WKWebExtension.Permission>
The currently granted permissions that have not expired.
var deniedPermissionMatchPatterns: [WKWebExtension.MatchPattern : Date]
The currently denied permission match patterns and their expiration dates.
var deniedPermissions: [WKWebExtension.Permission : Date]
The currently denied permissions and their expiration dates.
var errors: [any Error]
All errors that occurred in the extension context.
var focusedWindow: (any WKWebExtensionWindow)?
The window that currently has focus for this extension.
var grantedPermissionMatchPatterns: [WKWebExtension.MatchPattern : Date]
The currently granted permission match patterns and their expiration dates.
var grantedPermissions: [WKWebExtension.Permission : Date]
The currently granted permissions and their expiration dates.
var hasAccessToAllHosts: Bool
A Boolean value indicating if the currently granted permission match patterns set contains the <all_urls> pattern
or any * host patterns.
var hasAccessToAllURLs: Bool
A Boolean value indicating if the currently granted permission match patterns set contains the <all_urls> pattern.
var hasAccessToPrivateData: Bool
A Boolean value indicating if the extension has access to private data.
var hasContentModificationRules: Bool
A boolean value indicating whether the extension includes rules used for content modification or blocking.
var hasInjectedContent: Bool
A Boolean value indicating whether the extension has script or stylesheet content that can be injected into
webpages.
var hasRequestedOptionalAccessToAllHosts: Bool
A Boolean value indicating if the extension has requested optional access to all hosts.
var inspectionName: String?
The name shown when inspecting the background web view.
var isInspectable: Bool
Determines whether Web Inspector can inspect the WKWebView instances for this context.
var isLoaded: Bool
A Boolean value indicating if this context is loaded in an extension controller.
var openTabs: Set<AnyHashable>
A set of open tabs in all open windows that are exposed to this extension.
var openWindows: [any WKWebExtensionWindow]
The open windows that are exposed to this extension.
var optionsPageURL: URL?
The URL of the extension’s options page, if the extension has one.
var overrideNewTabPageURL: URL?
The URL to use as an alternative to the default new tab page, if the extension has one.
var uniqueIdentifier: String
A unique identifier used to distinguish the extension from other extensions and target it for messages.
var unsupportedAPIs: Set<String>!
Specifies unsupported APIs for this extension, making them undefined in JavaScript.
var webExtension: WKWebExtension
The extension this context represents.
var webExtensionController: WKWebExtensionController?
The extension controller this context is loaded in, otherwise nil if it isn’t loaded.
var webViewConfiguration: WKWebViewConfiguration?
The web view configuration to use for web views that load pages from this extension.
Instance Methods
func action(for: (any WKWebExtensionTab)?) -> WKWebExtension.Action?
Retrieves the extension action for a given tab, or the default action if nil is passed.
func clearUserGesture(in: any WKWebExtensionTab)
Called by the app to clear a user gesture in a specific tab.
func command(for: NSEvent) -> WKWebExtension.Command?
Retrieves the command associated with the given event without performing it.
func didActivateTab(any WKWebExtensionTab, previousActiveTab: (any WKWebExtensionTab)?)
Called by the app when a tab is activated to notify only this specific extension.
func didChangeTabProperties(WKWebExtension.TabChangedProperties, for: any WKWebExtensionTab)
Called by the app when the properties of a tab are changed to fire appropriate events with only this extension.
func didCloseTab(any WKWebExtensionTab, windowIsClosing: Bool)
Called by the app when a tab is closed to fire appropriate events with only this extension.
func didCloseWindow(any WKWebExtensionWindow)
Called by the app when a window is closed to fire appropriate events with only this extension.
func didDeselectTabs([any WKWebExtensionTab])
Called by the app when tabs are deselected to fire appropriate events with only this extension.
func didFocusWindow((any WKWebExtensionWindow)?)
Called by the app when a window gains focus to fire appropriate events with only this extension.
func didMoveTab(any WKWebExtensionTab, from: Int, in: (any WKWebExtensionWindow)?)
Called by the app when a tab is moved to fire appropriate events with only this extension.
func didOpenTab(any WKWebExtensionTab)
Called by the app when a new tab is opened to fire appropriate events with only this extension.
func didOpenWindow(any WKWebExtensionWindow)
Called by the app when a new window is opened to fire appropriate events with only this extension.
func didReplaceTab(any WKWebExtensionTab, with: any WKWebExtensionTab)
Called by the app when a tab is replaced by another tab to fire appropriate events with only this extension.
func didSelectTabs([any WKWebExtensionTab])
Called by the app when tabs are selected to fire appropriate events with only this extension.
func hasAccess(to: URL) -> Bool
Checks the specified URL against the currently granted permission match patterns.
func hasAccess(to: URL, in: (any WKWebExtensionTab)?) -> Bool
Checks the specified URL against the currently granted permission match patterns in a specific tab.
func hasActiveUserGesture(in: any WKWebExtensionTab) -> Bool
Indicates if a user gesture is currently active in the specified tab.
func hasInjectedContent(for: URL) -> Bool
Checks if the extension has script or stylesheet content that can be injected into the specified URL.
func hasPermission(WKWebExtension.Permission) -> Bool
Checks the specified permission against the currently granted permissions.
func hasPermission(WKWebExtension.Permission, in: (any WKWebExtensionTab)?) -> Bool
Checks the specified permission against the currently granted permissions in a specific tab.
func loadBackgroundContent(completionHandler: ((any Error)?) -> Void)
Loads the background content if needed for the extension.
func menuItems(for: any WKWebExtensionTab) -> [UIMenuElement]
Retrieves the menu items for a given tab.
func performAction(for: (any WKWebExtensionTab)?)
Performs the extension action associated with the specified tab or performs the default action if nil is passed.
func performCommand(WKWebExtension.Command)
Performs the specified command, triggering events specific to this extension.
func performCommand(for: UIKeyCommand) -> Bool
Performs the command associated with the given key command.
func performCommand(for: NSEvent) -> Bool
Performs the command associated with the given event.
func permissionStatus(for: WKWebExtension.Permission) -> WKWebExtensionContext.PermissionStatus
Checks the specified permission against the currently denied, granted, and requested permissions.
func permissionStatus(for: WKWebExtension.MatchPattern) -> WKWebExtensionContext.PermissionStatus
Checks the specified match pattern against the currently denied, granted, and requested permission match patterns.
func permissionStatus(for: URL) -> WKWebExtensionContext.PermissionStatus
Checks the specified URL against the currently denied, granted, and requested permission match patterns.
func permissionStatus(for: WKWebExtension.Permission, in: (any WKWebExtensionTab)?) ->
WKWebExtensionContext.PermissionStatus
Checks the specified permission against the currently denied, granted, and requested permissions.
func permissionStatus(for: URL, in: (any WKWebExtensionTab)?) -> WKWebExtensionContext.PermissionStatus
Checks the specified URL against the currently denied, granted, and requested permission match patterns.
func permissionStatus(for: WKWebExtension.MatchPattern, in: (any WKWebExtensionTab)?) ->
WKWebExtensionContext.PermissionStatus
Checks the specified match pattern against the currently denied, granted, and requested permission match patterns.
func setPermissionStatus(WKWebExtensionContext.PermissionStatus, for: WKWebExtension.Permission)
Sets the status of a permission with a distant future expiration date.
func setPermissionStatus(WKWebExtensionContext.PermissionStatus, for: URL)
Sets the permission status of a URL with a distant future expiration date.
func setPermissionStatus(WKWebExtensionContext.PermissionStatus, for: WKWebExtension.MatchPattern)
Sets the status of a match pattern with a distant future expiration date.
func setPermissionStatus(WKWebExtensionContext.PermissionStatus, for: URL, expirationDate: Date?)
Sets the permission status of a URL with a distant future expiration date.
func setPermissionStatus(WKWebExtensionContext.PermissionStatus, for: WKWebExtension.Permission, expirationDate:
Date?)
Sets the status of a permission with a specific expiration date.
func setPermissionStatus(WKWebExtensionContext.PermissionStatus, for: WKWebExtension.MatchPattern, expirationDate:
Date?)
Sets the status of a match pattern with a specific expiration date.
func userGesturePerformed(in: any WKWebExtensionTab)
Should be called by the app when a user gesture is performed in a specific tab.
Relationships
Inherits From
NSObject
Conforms To
CVarArg
CustomDebugStringConvertible
CustomStringConvertible
Equatable
Hashable
NSObjectProtocol
Sendable
See Also
Web extensions
class WKWebExtension
An object that encapsulates a web extension’s resources that the manifest file defines.
protocol WKWebExtensionTab
A protocol with methods that represent a tab to web extensions.
protocol WKWebExtensionWindow
A protocol with methods that represent a window to web extensions.
class WKWebExtensionController
An object that manages a set of loaded extension contexts.
protocol WKWebExtensionControllerDelegate
A group of methods you use to customize web extension interactions.

WKWebExtensionController
An object that manages a set of loaded extension contexts.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
@MainActor
class WKWebExtensionController
Overview
You can have one or more extension controller instances, allowing different parts of the app to use different sets
of extensions.

You can associate a controller with WKWebView using the webExtensionController property on WKWebViewConfiguration.

Topics
Initializers
init()
Returns a web extension controller initialized with the default configuration.
init(configuration: WKWebExtensionController.Configuration)
Returns a web extension controller initialized with the specified configuration.
Instance Properties
var configuration: WKWebExtensionController.Configuration
A copy of the configuration with which the web extension controller was initialized.
var delegate: (any WKWebExtensionControllerDelegate)?
The extension controller delegate.
var extensionContexts: Set<WKWebExtensionContext>
A set of all the currently loaded extension contexts.
var extensions: Set<WKWebExtension>
A set of all the currently loaded extensions.
Instance Methods
func didActivateTab(any WKWebExtensionTab, previousActiveTab: (any WKWebExtensionTab)?)
Should be called by the app when a tab is activated to notify all loaded web extensions.
func didChangeTabProperties(WKWebExtension.TabChangedProperties, for: any WKWebExtensionTab)
Should be called by the app when the properties of a tab are changed to fire appropriate events with all loaded web
 extensions.
func didCloseTab(any WKWebExtensionTab, windowIsClosing: Bool)
Should be called by the app when a tab is closed to fire appropriate events with all loaded web extensions.
func didCloseWindow(any WKWebExtensionWindow)
Should be called by the app when a window is closed to fire appropriate events with all loaded web extensions.
func didDeselectTabs([any WKWebExtensionTab])
Should be called by the app when tabs are deselected to fire appropriate events with all loaded web extensions.
func didFocusWindow((any WKWebExtensionWindow)?)
Should be called by the app when a window gains focus to fire appropriate events with all loaded web extensions.
func didMoveTab(any WKWebExtensionTab, from: Int, in: (any WKWebExtensionWindow)?)
Should be called by the app when a tab is moved to fire appropriate events with all loaded web extensions.
func didOpenTab(any WKWebExtensionTab)
Should be called by the app when a new tab is opened to fire appropriate events with all loaded web extensions.
func didOpenWindow(any WKWebExtensionWindow)
Should be called by the app when a new window is opened to fire appropriate events with all loaded web extensions.
func didReplaceTab(any WKWebExtensionTab, with: any WKWebExtensionTab)
Should be called by the app when a tab is replaced by another tab to fire appropriate events with all loaded web
extensions.
func didSelectTabs([any WKWebExtensionTab])
Should be called by the app when tabs are selected to fire appropriate events with all loaded web extensions.
func extensionContext(for: URL) -> WKWebExtensionContext?
Returns a loaded extension context matching the specified URL.
func extensionContext(for: WKWebExtension) -> WKWebExtensionContext?
Returns a loaded extension context for the specified extension.
func fetchDataRecord(ofTypes: Set<WKWebExtension.DataType>, for: WKWebExtensionContext, completionHandler:
(WKWebExtension.DataRecord?) -> Void)
Fetches a data record containing the given extension data types for a specific known web extension context.
func fetchDataRecords(ofTypes: Set<WKWebExtension.DataType>, completionHandler: ([WKWebExtension.DataRecord]) ->
Void)
Fetches data records containing the given extension data types for all known extensions.
func load(WKWebExtensionContext) throws
Loads the specified extension context.
func removeData(ofTypes: Set<WKWebExtension.DataType>, from: [WKWebExtension.DataRecord], completionHandler: () ->
Void)
Removes extension data of the given types for the given data records.
func unload(WKWebExtensionContext) throws
Unloads the specified extension context.
Type Properties
class var allExtensionDataTypes: Set<WKWebExtension.DataType>
Returns a set of all available extension data types.
Relationships
Inherits From
NSObject
Conforms To
CVarArg
CustomDebugStringConvertible
CustomStringConvertible
Equatable
Hashable
NSObjectProtocol
Sendable
See Also
Web extensions
class WKWebExtension
An object that encapsulates a web extension’s resources that the manifest file defines.
protocol WKWebExtensionTab
A protocol with methods that represent a tab to web extensions.
protocol WKWebExtensionWindow
A protocol with methods that represent a window to web extensions.
class WKWebExtensionContext
An object that represents the runtime environment for a web extension.
protocol WKWebExtensionControllerDelegate
A group of methods you use to customize web extension interactions.

WKWebExtensionControllerDelegate
A group of methods you use to customize web extension interactions.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
@MainActor
protocol WKWebExtensionControllerDelegate : NSObjectProtocol
Topics
Instance Methods
func webExtensionController(WKWebExtensionController, connectUsing: WKWebExtension.MessagePort, for:
WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called when an extension context wants to establish a persistent connection to an application.
func webExtensionController(WKWebExtensionController, didUpdate: WKWebExtension.Action, forExtensionContext:
WKWebExtensionContext)
Called when an action’s properties are updated.
func webExtensionController(WKWebExtensionController, focusedWindowFor: WKWebExtensionContext) -> (any
WKWebExtensionWindow)?
Called when an extension context requests the currently focused window.
func webExtensionController(WKWebExtensionController, openNewTabUsing: WKWebExtension.TabConfiguration, for:
WKWebExtensionContext, completionHandler: ((any WKWebExtensionTab)?, (any Error)?) -> Void)
Called when an extension context requests a new tab to be opened.
func webExtensionController(WKWebExtensionController, openNewWindowUsing: WKWebExtension.WindowConfiguration, for:
WKWebExtensionContext, completionHandler: ((any WKWebExtensionWindow)?, (any Error)?) -> Void)
Called when an extension context requests a new window to be opened.
func webExtensionController(WKWebExtensionController, openOptionsPageFor: WKWebExtensionContext, completionHandler:
 ((any Error)?) -> Void)
Called when an extension context requests its options page to be opened.
func webExtensionController(WKWebExtensionController, openWindowsFor: WKWebExtensionContext) -> [any
WKWebExtensionWindow]
Called when an extension context requests the list of ordered open windows.
func webExtensionController(WKWebExtensionController, presentActionPopup: WKWebExtension.Action, for:
WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called when a popup is requested to be displayed for a specific action.
func webExtensionController(WKWebExtensionController, promptForPermissionMatchPatterns:
Set<WKWebExtension.MatchPattern>, in: (any WKWebExtensionTab)?, for: WKWebExtensionContext, completionHandler:
(Set<WKWebExtension.MatchPattern>, Date?) -> Void)
Called when an extension context requests access to a set of match patterns.
func webExtensionController(WKWebExtensionController, promptForPermissionToAccess: Set<URL>, in: (any
WKWebExtensionTab)?, for: WKWebExtensionContext, completionHandler: (Set<URL>, Date?) -> Void)
Called when an extension context requests access to a set of URLs.
func webExtensionController(WKWebExtensionController, promptForPermissions: Set<WKWebExtension.Permission>, in:
(any WKWebExtensionTab)?, for: WKWebExtensionContext, completionHandler: (Set<WKWebExtension.Permission>, Date?) ->
 Void)
Called when an extension context requests permissions.
func webExtensionController(WKWebExtensionController, sendMessage: Any, toApplicationWithIdentifier: String?, for:
WKWebExtensionContext, replyHandler: (Any?, (any Error)?) -> Void)
Called when an extension context wants to send a one-time message to an application.
Relationships
Inherits From
NSObjectProtocol
See Also
Web extensions
class WKWebExtension
An object that encapsulates a web extension’s resources that the manifest file defines.
protocol WKWebExtensionTab
A protocol with methods that represent a tab to web extensions.
protocol WKWebExtensionWindow
A protocol with methods that represent a window to web extensions.
class WKWebExtensionContext
An object that represents the runtime environment for a web extension.
class WKWebExtensionController
An object that manages a set of loaded extension contexts.
