    WebKit WKWebExtension
Class
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
This class reads and parses the manifest.json file along with the supporting resources like icons and localizations.
Topics
Classes
class Action
An object that encapsulates the properties for an individual web extension action.
class Command
An object that encapsulates the properties for an individual web extension command.
class DataRecord
An object that represents a record of stored data for a specific web extension context.
class MatchPattern
An object that represents a way to specify groups of URLs.
class MessagePort
An object that manages message-based communication with a web extension.
class TabConfiguration
An object that encapsulates configuration options for a tab in an extension.
class WindowConfiguration
An object that encapsulates configuration options for a window in an extension.
class Configuration
A WKWebExtensionController.Configuration object with which to initialize a web extension controller.
Structures
struct DataType
Constants for specifying data types for a WKWebExtension.DataRecord.
struct Error
Constants that indicate errors in the WKWebExtension domain.
struct Permission
Constants for specifying permission in a WKWebExtensionContext.
struct TabChangedProperties
Constants the web extension controller and web extension context use to indicate tab changes.
Enumerations
enum WindowState
Constants used by WKWebExtensionWindow to indicate possible states of a window.
enum WindowType
Constants used by WKWebExtensionWindow to indicate the type of a window.
Initializers
convenience init(appExtensionBundle: Bundle) async throws
Creates a web extension initialized with a specified app extension bundle.
convenience init(resourceBaseURL: URL) async throws
Creates a web extension initialized with a specified resource base URL, which can point to either a directory or a ZIP archive.
Instance Properties
var allRequestedMatchPatterns: Set<WKWebExtension.MatchPattern>
The set of websites that the extension requires access to for injected content and for receiving messages from websites.
var defaultLocale: Locale?
The default locale for the extension.
var displayActionLabel: String?
The default localized extension action label.
var displayDescription: String?
The localized extension description.
var displayName: String?
The localized extension name.
var displayShortName: String?
The localized extension short name.
var displayVersion: String?
The localized extension display version.
var errors: [any Error]
An array of all errors that occurred during the processing of the extension.
var hasBackgroundContent: Bool
A Boolean value indicating whether the extension has background content that can run when needed.
var hasCommands: Bool
A Boolean value indicating whether the extension includes commands that users can invoke.
var hasContentModificationRules: Bool
A Boolean value indicating whether the extension includes rules used for content modification or blocking.
var hasInjectedContent: Bool
A Boolean value indicating whether the extension has script or stylesheet content that can be injected into webpages.
var hasOptionsPage: Bool
A Boolean value indicating whether the extension has an options page.
var hasOverrideNewTabPage: Bool
A Boolean value indicating whether the extension provides an alternative to the default new tab page.
var hasPersistentBackgroundContent: Bool
A Boolean value indicating whether the extension has background content that stays in memory as long as the extension is loaded.
var manifest: [String : Any]
The parsed manifest as a dictionary.
var manifestVersion: Double
The parsed manifest version, or 0 if there is no version specified in the manifest.
var optionalPermissionMatchPatterns: Set<WKWebExtension.MatchPattern>
The set of websites that the extension may need access to for optional functionality.
var optionalPermissions: Set<WKWebExtension.Permission>
The set of permissions that the extension may need for optional functionality.
var requestedPermissionMatchPatterns: Set<WKWebExtension.MatchPattern>
The set of websites that the extension requires access to for its base functionality.
var requestedPermissions: Set<WKWebExtension.Permission>
The set of permissions that the extension requires for its base functionality.
var version: String?
The extension version.
Instance Methods
func actionIcon(for: CGSize) -> UIImage?
Returns the default action icon for the specified size.
func icon(for: CGSize) -> UIImage?
Returns the extension’s icon image for the specified size.
func supportsManifestVersion(Double) -> Bool
Checks if a manifest version is supported by the extension.
Relationships
Inherits From
*         NSObject
Conforms To
*         CVarArg
*         CustomDebugStringConvertible
*         CustomStringConvertible
*         Equatable
*         Hashable
*         NSObjectProtocol
*         Sendable
See Also
Web extensions
protocol WKWebExtensionTab
A protocol with methods that represent a tab to web extensions.
protocol WKWebExtensionWindow
A protocol with methods that represent a window to web extensions.
class WKWebExtensionContext
An object that represents the runtime environment for a web extension.
class WKWebExtensionController
An object that manages a set of loaded extension contexts.
protocol WKWebExtensionControllerDelegate
A group of methods you use to customize web extension interactions.
Current page is WKWebExtension
           WebKit WKWebExtension WKWebExtension.Action
Class
WKWebExtension.Action
An object that encapsulates the properties for an individual web extension action.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
@MainActor
class Action
Overview
This class provides access to action properties, such as pop-up, icon, or title, with tab-specific values.
Topics
Instance Properties
var associatedTab: (any WKWebExtensionTab)?
The tab that this action is associated with, or nil if it’s the default action.
var badgeText: String
The badge text for the action.
var hasUnreadBadgeText: Bool
A Boolean value indicating whether the badge text is unread.
var inspectionName: String?
The name shown when inspecting the pop-up web view.
var isEnabled: Bool
A Boolean value indicating whether the action is enabled.
var label: String
The localized display label for the action.
var menuItems: [UIMenuElement]
The menu items provided by the extension for this action.
var popupPopover: NSPopover?
A popover that presents a web view loaded with the pop-up page for this action, or nil if no popup is specified.
var popupViewController: UIViewController?
A view controller that presents a web view loaded with the pop-up page for this action, or nil if no popup is specified.
var popupWebView: WKWebView?
A web view loaded with the pop-up page for this action, or nil if no pop-up is specified.
var presentsPopup: Bool
A Boolean value indicating whether the action has a pop-up.
var webExtensionContext: WKWebExtensionContext?
The extension context to which this action is related.
Instance Methods
func closePopup()
Triggers the dismissal process of the pop-up.
func icon(for: CGSize) -> UIImage?
Returns the action icon for the specified size.
Relationships
Inherits From
*         NSObject
Conforms To
*         CVarArg
*         CustomDebugStringConvertible
*         CustomStringConvertible
*         Equatable
*         Hashable
*         NSObjectProtocol
*         Sendable
See Also
Classes
class Command
An object that encapsulates the properties for an individual web extension command.
class DataRecord
An object that represents a record of stored data for a specific web extension context.
class MatchPattern
An object that represents a way to specify groups of URLs.
class MessagePort
An object that manages message-based communication with a web extension.
class TabConfiguration
An object that encapsulates configuration options for a tab in an extension.
class WindowConfiguration
An object that encapsulates configuration options for a window in an extension.
class Configuration
A WKWebExtensionController.Configuration object with which to initialize a web extension controller.
Current page is WKWebExtension.Action
         WebKit WKWebExtension WKWebExtension.Command
Class
WKWebExtension.Command
An object that encapsulates the properties for an individual web extension command.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
@MainActor
class Command
Overview
Provides access to command properties such as a unique identifier, a descriptive title, and shortcut keys. Commands can be used by a web extension to perform specific actions within a web extension context, such toggling features, or interacting with web content. These commands enhance the functionality of the extension by allowing users to invoke actions quickly.
Topics
Instance Properties
var activationKey: String?
The primary key used to trigger the command, distinct from any modifier flags.
var id: String
A unique identifier for the command.
var keyCommand: UIKeyCommand?
A key command representation of the web extension command for use in the responder chain.
var menuItem: UIMenuElement
A menu item representation of the web extension command for use in menus.
var modifierFlags: UIKeyModifierFlags
The modifier flags used with the activation key to trigger the command.
var title: String
A descriptive title for the command to help discoverability.
var webExtensionContext: WKWebExtensionContext?
The web extension context associated with the command.
Relationships
Inherits From
*         NSObject
Conforms To
*         CVarArg
*         CustomDebugStringConvertible
*         CustomStringConvertible
*         Equatable
*         Hashable
*         NSObjectProtocol
*         Sendable
See Also
Classes
class Action
An object that encapsulates the properties for an individual web extension action.
class DataRecord
An object that represents a record of stored data for a specific web extension context.
class MatchPattern
An object that represents a way to specify groups of URLs.
class MessagePort
An object that manages message-based communication with a web extension.
class TabConfiguration
An object that encapsulates configuration options for a tab in an extension.
class WindowConfiguration
An object that encapsulates configuration options for a window in an extension.
class Configuration
A WKWebExtensionController.Configuration object with which to initialize a web extension controller.
Current page is WKWebExtension.Command
         WebKit WKWebExtension WKWebExtension.DataRecord
Class
WKWebExtension.DataRecord
An object that represents a record of stored data for a specific web extension context.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
@MainActor
class DataRecord
Overview
Contains properties and methods to query the data types and sizes.
Topics
Structures
struct Error
Constants that indicate errors in the WKWebExtension.DataRecord domain.
Instance Properties
var containedDataTypes: Set<WKWebExtension.DataType>
The set of data types contained in this data record.
var displayName: String
The display name for the web extension to which this data record belongs.
var errors: [any Error]
An array of errors that may have occurred when either calculating or deleting storage.
var totalSizeInBytes: Int
The total size in bytes of all data types contained in this data record.
var uniqueIdentifier: String
Unique identifier for the web extension context to which this data record belongs.
Instance Methods
func sizeInBytes(ofTypes: Set<WKWebExtension.DataType>) -> Int
Retrieves the size in bytes of the specific data types in this data record.
Relationships
Inherits From
*         NSObject
Conforms To
*         CVarArg
*         CustomDebugStringConvertible
*         CustomStringConvertible
*         Equatable
*         Hashable
*         NSObjectProtocol
*         Sendable
See Also
Classes
class Action
An object that encapsulates the properties for an individual web extension action.
class Command
An object that encapsulates the properties for an individual web extension command.
class MatchPattern
An object that represents a way to specify groups of URLs.
class MessagePort
An object that manages message-based communication with a web extension.
class TabConfiguration
An object that encapsulates configuration options for a tab in an extension.
class WindowConfiguration
An object that encapsulates configuration options for a window in an extension.
class Configuration
A WKWebExtensionController.Configuration object with which to initialize a web extension controller.
Current page is WKWebExtension.DataRecord
         WebKit WKWebExtension WKWebExtension.MatchPattern
Class
WKWebExtension.MatchPattern
An object that represents a way to specify groups of URLs.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
@MainActor
class MatchPattern
Overview
All match patterns are specified as strings. Apart from the special <all_urls> pattern, match patterns consist of three parts: scheme, host, and path.
Topics
Errors
struct Error
Constants that indicate errors in the WKWebExtension.MatchPattern domain.
enum Code
Constants that indicate errors in the WKWebExtension.MatchPattern domain.
class let errorDomain: String
A string that identifies the error domain.
Structures
struct Options
Constants used by WKWebExtension.MatchPattern to indicate matching options.
Initializers
init(scheme: String, host: String, path: String) throws
Returns a pattern object for the specified scheme, host, and path strings.
init(string: String) throws
Returns a pattern object for the specified pattern string.
Instance Properties
var host: String?
The host part of the pattern string, unless matchesAllURLs is YES.
var matchesAllHosts: Bool
A Boolean value that indicates if the pattern is <all_urls> or has * as the host.
var matchesAllURLs: Bool
A Boolean value that indicates if the pattern is <all_urls>.
var path: String?
The path part of the pattern string, unless matchesAllURLs is YES.
var scheme: String?
The scheme part of the pattern string, unless matchesAllURLs is YES.
var string: String
The original pattern string.
Instance Methods
func matches(URL?) -> Bool
Matches the receiver pattern against the specified URL.
func matches(WKWebExtension.MatchPattern?) -> Bool
Matches the receiver pattern against the specified pattern.
func matches(URL?, options: WKWebExtension.MatchPattern.Options) -> Bool
Matches the receiver pattern against the specified URL with options.
func matches(WKWebExtension.MatchPattern?, options: WKWebExtension.MatchPattern.Options) -> Bool
Matches the receiver pattern against the specified pattern with options.
Type Methods
class func allHostsAndSchemes() -> Self
Returns a pattern object that has * for scheme, host, and path.
class func allURLs() -> Self
Returns a pattern object for <all_urls>.
class func registerCustomURLScheme(String)
Registers a custom URL scheme that can be used in match patterns.
Relationships
Inherits From
*         NSObject
Conforms To
*         CVarArg
*         CustomDebugStringConvertible
*         CustomStringConvertible
*         Equatable
*         Hashable
*         NSCoding
*         NSCopying
*         NSObjectProtocol
*         NSSecureCoding
*         Sendable
See Also
Classes
class Action
An object that encapsulates the properties for an individual web extension action.
class Command
An object that encapsulates the properties for an individual web extension command.
class DataRecord
An object that represents a record of stored data for a specific web extension context.
class MessagePort
An object that manages message-based communication with a web extension.
class TabConfiguration
An object that encapsulates configuration options for a tab in an extension.
class WindowConfiguration
An object that encapsulates configuration options for a window in an extension.
class Configuration
A WKWebExtensionController.Configuration object with which to initialize a web extension controller.
Current page is WKWebExtension.MatchPattern
 

    WebKit WKWebExtension WKWebExtension.MessagePort
Class
WKWebExtension.MessagePort
An object that manages message-based communication with a web extension.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
@MainActor
class MessagePort
Overview
Contains properties and methods to handle message exchanges with a web extension.
Topics
Structures
struct Error
Constants that indicate errors in the WKWebExtension.MessagePort domain.
Instance Properties
var applicationIdentifier: String?
The unique identifier for the app to which this port should be connected.
var disconnectHandler: (((any Error)?) -> Void)?
The block to be executed when the port disconnects.
var isDisconnected: Bool
Indicates whether the message port is disconnected.
var messageHandler: ((Any?, (any Error)?) -> Void)?
The block to be executed when a message is received from the web extension.
Instance Methods
func disconnect()
Disconnects the port, terminating all further messages.
func disconnect(throwing: (any Error)?)
Disconnects the port, terminating all further messages with an optional error.
func sendMessage(Any?, completionHandler: (((any Error)?) -> Void)?)
Sends a message to the connected web extension.
Relationships
Inherits From
*         NSObject
Conforms To
*         CVarArg
*         CustomDebugStringConvertible
*         CustomStringConvertible
*         Equatable
*         Hashable
*         NSObjectProtocol
*         Sendable
See Also
Classes
class Action
An object that encapsulates the properties for an individual web extension action.
class Command
An object that encapsulates the properties for an individual web extension command.
class DataRecord
An object that represents a record of stored data for a specific web extension context.
class MatchPattern
An object that represents a way to specify groups of URLs.
class TabConfiguration
An object that encapsulates configuration options for a tab in an extension.
class WindowConfiguration
An object that encapsulates configuration options for a window in an extension.
class Configuration
A WKWebExtensionController.Configuration object with which to initialize a web extension controller.
Current page is WKWebExtension.MessagePort
       WebKit WKWebExtension WKWebExtension.TabConfiguration
Class
WKWebExtension.TabConfiguration
An object that encapsulates configuration options for a tab in an extension.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
@MainActor
class TabConfiguration
Overview
This class holds various options that influence the behavior and initial state of a tab.
The app retains the discretion to disregard any or all of these options, or even opt not to create a tab.
Topics
Instance Properties
var index: Int
Indicates the position where the tab should be opened within the window.
var parentTab: (any WKWebExtensionTab)?
Indicates the parent tab with which the tab should be related.
var shouldAddToSelection: Bool
Indicates whether the tab should be added to the current tab selection.
var shouldBeActive: Bool
Indicates whether the tab should be the active tab.
var shouldBeMuted: Bool
Indicates whether the tab should be muted.
var shouldBePinned: Bool
Indicates whether the tab should be pinned.
var shouldReaderModeBeActive: Bool
Indicates whether reader mode in the tab should be active.
var url: URL?
Indicates the initial URL for the tab.
var window: (any WKWebExtensionWindow)?
Indicates the window where the tab should be opened.
Relationships
Inherits From
*         NSObject
Conforms To
*         CVarArg
*         CustomDebugStringConvertible
*         CustomStringConvertible
*         Equatable
*         Hashable
*         NSObjectProtocol
*         Sendable
See Also
Classes
class Action
An object that encapsulates the properties for an individual web extension action.
class Command
An object that encapsulates the properties for an individual web extension command.
class DataRecord
An object that represents a record of stored data for a specific web extension context.
class MatchPattern
An object that represents a way to specify groups of URLs.
class MessagePort
An object that manages message-based communication with a web extension.
class WindowConfiguration
An object that encapsulates configuration options for a window in an extension.
class Configuration
A WKWebExtensionController.Configuration object with which to initialize a web extension controller.
Current page is WKWebExtension.TabConfiguration
        WebKit WKWebExtension WKWebExtension.WindowConfiguration
Class
WKWebExtension.WindowConfiguration
An object that encapsulates configuration options for a window in an extension.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
@MainActor
class WindowConfiguration
Overview
This class holds various options that influence the behavior and initial state of a window.
The app retains the discretion to disregard any or all of these options, or even opt not to create a window.
Topics
Instance Properties
var frame: CGRect
Indicates the frame where the window should be positioned on the main screen.
var shouldBeFocused: Bool
Indicates whether the window should be focused.
var shouldBePrivate: Bool
Indicates whether the window should be private.
var tabURLs: [URL]
Indicates the URLs that the window should initially load as tabs.
var tabs: [any WKWebExtensionTab]
Indicates the existing tabs that should be moved to the window.
var windowState: WKWebExtension.WindowState
Indicates the window state for the window.
var windowType: WKWebExtension.WindowType
Indicates the window type for the window.
Relationships
Inherits From
*         NSObject
Conforms To
*         CVarArg
*         CustomDebugStringConvertible
*         CustomStringConvertible
*         Equatable
*         Hashable
*         NSObjectProtocol
*         Sendable
See Also
Classes
class Action
An object that encapsulates the properties for an individual web extension action.
class Command
An object that encapsulates the properties for an individual web extension command.
class DataRecord
An object that represents a record of stored data for a specific web extension context.
class MatchPattern
An object that represents a way to specify groups of URLs.
class MessagePort
An object that manages message-based communication with a web extension.
class TabConfiguration
An object that encapsulates configuration options for a tab in an extension.
class Configuration
A WKWebExtensionController.Configuration object with which to initialize a web extension controller.
Current page is WKWebExtension.WindowConfiguration
        WebKit WKWebExtensionController WKWebExtensionController.Configuration
Class
WKWebExtensionController.Configuration
A WKWebExtensionController.Configuration object with which to initialize a web extension controller.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
@MainActor
class Configuration
Overview
Contains properties used to configure a WKWebExtensionController.
Topics
Initializers
convenience init(identifier: UUID)
Returns a new configuration that is persistent and unique for the specified identifier.
Instance Properties
var defaultWebsiteDataStore: WKWebsiteDataStore!
The default data store for website data and cookie access in extension contexts.
var identifier: UUID?
The unique identifier used for persistent configuration storage, or nil when it is the default or not persistent.
var isPersistent: Bool
A Boolean value indicating if this context will write data to the the file system.
var webViewConfiguration: WKWebViewConfiguration!
The web view configuration to be used as a basis for configuring web views in extension contexts.
Type Methods
class func `default`() -> Self
Returns a new default configuration that is persistent and not unique.
class func nonPersistent() -> Self
Returns a new non-persistent configuration.
Relationships
Inherits From
*         NSObject
Conforms To
*         CVarArg
*         CustomDebugStringConvertible
*         CustomStringConvertible
*         Equatable
*         Hashable
*         NSCoding
*         NSCopying
*         NSObjectProtocol
*         NSSecureCoding
*         Sendable
See Also
Classes
class Action
An object that encapsulates the properties for an individual web extension action.
class Command
An object that encapsulates the properties for an individual web extension command.
class DataRecord
An object that represents a record of stored data for a specific web extension context.
class MatchPattern
An object that represents a way to specify groups of URLs.
class MessagePort
An object that manages message-based communication with a web extension.
class TabConfiguration
An object that encapsulates configuration options for a tab in an extension.
class WindowConfiguration
An object that encapsulates configuration options for a window in an extension.
Current page is WKWebExtensionController.Configuration
         WebKit WKWebExtension WKWebExtension.DataType
Structure
WKWebExtension.DataType
Constants for specifying data types for a WKWebExtension.DataRecord.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
struct DataType
Topics
Constants
static let local: WKWebExtension.DataType
Specifies local storage, including browser.storage.local.
static let session: WKWebExtension.DataType
Specifies session storage, including browser.storage.session.
static let synchronized: WKWebExtension.DataType
Specifies synchronized storage, including browser.storage.sync.
Initializers
init(rawValue: String)
Creates a data type from a raw value you provide.
Relationships
Conforms To
*         Equatable
*         Hashable
*         RawRepresentable
*         Sendable
*         SendableMetatype
See Also
Structures
struct Error
Constants that indicate errors in the WKWebExtension domain.
struct Permission
Constants for specifying permission in a WKWebExtensionContext.
struct TabChangedProperties
Constants the web extension controller and web extension context use to indicate tab changes.
Current page is WKWebExtension.DataType
    Skip Navigation





Documentation
Open Menu
*         Swift 





    •    WebKit WKWebExtension WKWebExtension.Error
Structure
WKWebExtension.Error
Constants that indicate errors in the WKWebExtension domain.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
struct Error
Topics
Type Properties
static var errorDomain: String
static var invalidArchive: WKWebExtension.Error.Code
Indicates that the archive file is invalid or corrupt.
static var invalidBackgroundPersistence: WKWebExtension.Error.Code
Indicates that the extension specified background persistence that was not compatible with the platform or features requested.
static var invalidDeclarativeNetRequestEntry: WKWebExtension.Error.Code
Indicates that an invalid declarative net request entry was encountered.
static var invalidManifest: WKWebExtension.Error.Code
Indicates that an invalid manifest.json was encountered.
static var invalidManifestEntry: WKWebExtension.Error.Code
Indicates that an invalid manifest entry was encountered.
static var invalidResourceCodeSignature: WKWebExtension.Error.Code
Indicates that a resource failed the bundle’s code signature checks.
static var resourceNotFound: WKWebExtension.Error.Code
Indicates that a specified resource was not found on disk.
static var unknown: WKWebExtension.Error.Code
Indicates that an unknown error occurred.
static var unsupportedManifestVersion: WKWebExtension.Error.Code
Indicates that the manifest version is not supported.
Relationships
Conforms To
*         CustomNSError
*         Equatable
*         Error
*         Hashable
*         Sendable
*         SendableMetatype
See Also
Structures
struct DataType
Constants for specifying data types for a WKWebExtension.DataRecord.
struct Permission
Constants for specifying permission in a WKWebExtensionContext.
struct TabChangedProperties
Constants the web extension controller and web extension context use to indicate tab changes.
Current page is WKWebExtension.Error
       WebKit WKWebExtension WKWebExtension.Permission
Structure
WKWebExtension.Permission
Constants for specifying permission in a WKWebExtensionContext.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
struct Permission
Topics
Constants
static let activeTab: WKWebExtension.Permission
A request indicating that when a person interacts with the extension, the system grants extra permissions for the active tab only.
static let alarms: WKWebExtension.Permission
A request for access to the browser.alarms APIs.
static let clipboardWrite: WKWebExtension.Permission
A request for access to write to the clipboard.
static let contextMenus: WKWebExtension.Permission
A request for access to the browser.contextMenus APIs.
static let cookies: WKWebExtension.Permission
A request for access to the browser.cookies APIs.
static let declarativeNetRequest: WKWebExtension.Permission
A request for access to the browser.declarativeNetRequest APIs.
static let declarativeNetRequestFeedback: WKWebExtension.Permission
A request for access to the browser.declarativeNetRequest APIs with extra information on matched rules.
static let declarativeNetRequestWithHostAccess: WKWebExtension.Permission
A request for access to the browser.declarativeNetRequest APIs with the ability to modify or redirect requests.
static let menus: WKWebExtension.Permission
A request for access to the browser.menus APIs.
static let nativeMessaging: WKWebExtension.Permission
A request for access to send messages to the app extension bundle.
static let scripting: WKWebExtension.Permission
A request for access to the browser.scripting APIs.
static let storage: WKWebExtension.Permission
A request for access to the browser.storage APIs.
static let tabs: WKWebExtension.Permission
A request for access to extra information on the browser.tabs APIs.
static let unlimitedStorage: WKWebExtension.Permission
A request for access to an unlimited quota on the browser.storage.local APIs.
static let webNavigation: WKWebExtension.Permission
A request for access to the browser.webNavigation APIs.
static let webRequest: WKWebExtension.Permission
A request for access to the browser.webRequest APIs.
Initializers
init(String)
init(rawValue: String)
Relationships
Conforms To
*         Equatable
*         Hashable
*         RawRepresentable
*         Sendable
*         SendableMetatype
See Also
Structures
struct DataType
Constants for specifying data types for a WKWebExtension.DataRecord.
struct Error
Constants that indicate errors in the WKWebExtension domain.
struct TabChangedProperties
Constants the web extension controller and web extension context use to indicate tab changes.
Current page is WKWebExtension.Permission
       WebKit WKWebExtension WKWebExtension.TabChangedProperties
Structure
WKWebExtension.TabChangedProperties
Constants the web extension controller and web extension context use to indicate tab changes.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
struct TabChangedProperties
Topics
Initializers
init(rawValue: UInt)
Type Properties
static var URL: WKWebExtension.TabChangedProperties
Indicates the URL changed.
static var loading: WKWebExtension.TabChangedProperties
Indicates the loading state changed.
static var muted: WKWebExtension.TabChangedProperties
Indicates the muted state changed.
static var pinned: WKWebExtension.TabChangedProperties
Indicates the pinned state changed.
static var playingAudio: WKWebExtension.TabChangedProperties
Indicates the audio playback state changed.
static var readerMode: WKWebExtension.TabChangedProperties
Indicates the reader mode state changed.
static var size: WKWebExtension.TabChangedProperties
Indicates the size changed.
static var title: WKWebExtension.TabChangedProperties
Indicates the title changed.
static var zoomFactor: WKWebExtension.TabChangedProperties
Indicates the zoom factor changed.
Relationships
Conforms To
*         BitwiseCopyable
*         Equatable
*         ExpressibleByArrayLiteral
*         OptionSet
*         RawRepresentable
*         Sendable
*         SendableMetatype
*         SetAlgebra
See Also
Structures
struct DataType
Constants for specifying data types for a WKWebExtension.DataRecord.
struct Error
Constants that indicate errors in the WKWebExtension domain.
struct Permission
Constants for specifying permission in a WKWebExtensionContext.
Current page is WKWebExtension.TabChangedProperties
       WebKit WKWebExtension WKWebExtension.WindowState
Enumeration
WKWebExtension.WindowState
Constants used by WKWebExtensionWindow to indicate possible states of a window.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
enum WindowState
Topics
Enumeration Cases
case fullscreen
Indicates a window is in full-screen mode.
case maximized
Indicates a window is maximized.
case minimized
Indicates a window is minimized.
case normal
Indicates a window is in its normal state.
Initializers
init?(rawValue: Int)
Relationships
Conforms To
*         BitwiseCopyable
*         Equatable
*         Hashable
*         RawRepresentable
*         Sendable
*         SendableMetatype
See Also
Enumerations
enum WindowType
Constants used by WKWebExtensionWindow to indicate the type of a window.
Current page is WKWebExtension.WindowState
       WebKit WKWebExtension WKWebExtension.WindowType
Enumeration
WKWebExtension.WindowType
Constants used by WKWebExtensionWindow to indicate the type of a window.
iOS 18.4+
iPadOS 18.4+
Mac Catalyst 18.4+
macOS 15.4+
visionOS 2.4+
enum WindowType
Topics
Enumeration Cases
case normal
Indicates a normal window.
case popup
Indicates a pop-up window.
Initializers
init?(rawValue: Int)
Relationships
Conforms To
*         BitwiseCopyable
*         Equatable
*         Hashable
*         RawRepresentable
*         Sendable
*         SendableMetatype
See Also
Enumerations
enum WindowState
Constants used by WKWebExtensionWindow to indicate possible states of a window.
Current page is WKWebExtension.WindowType
       WebKit WKWebExtensionTab
Protocol
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
func activate(for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to activate the tab, making it frontmost.
func close(for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to close the tab.
func detectWebpageLocale(for: WKWebExtensionContext, completionHandler: (Locale?, (any Error)?) -> Void)
Called to detect the locale of the webpage currently loaded in the tab.
func duplicate(using: WKWebExtension.TabConfiguration, for: WKWebExtensionContext, completionHandler: ((any WKWebExtensionTab)?, (any Error)?) -> Void)
Called to duplicate the tab.
func goBack(for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to navigate the tab to the previous page in its history.
func goForward(for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to navigate the tab to the next page in its history.
func indexInWindow(for: WKWebExtensionContext) -> Int
Called when the index of the tab in the window is needed.
func isLoadingComplete(for: WKWebExtensionContext) -> Bool
Called to check if the tab has finished loading.
func isMuted(for: WKWebExtensionContext) -> Bool
Called to check if the tab is currently muted.
func isPinned(for: WKWebExtensionContext) -> Bool
Called when the pinned state of the tab is needed.
func isPlayingAudio(for: WKWebExtensionContext) -> Bool
Called to check if the tab is currently playing audio.
func isReaderModeActive(for: WKWebExtensionContext) -> Bool
Called to check if the tab is currently showing reader mode.
func isReaderModeAvailable(for: WKWebExtensionContext) -> Bool
Called to check if reader mode is available for the tab.
func isSelected(for: WKWebExtensionContext) -> Bool
Called when the selected state of the tab is needed.
func loadURL(URL, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to load a URL in the tab.
func parentTab(for: WKWebExtensionContext) -> (any WKWebExtensionTab)?
Called when the parent tab for the tab is needed.
func pendingURL(for: WKWebExtensionContext) -> URL?
Called when the pending URL of the tab is needed.
func reload(fromOrigin: Bool, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to reload the current page in the tab.
func setMuted(Bool, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to set the mute state of the tab.
func setParentTab((any WKWebExtensionTab)?, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to set or clear the parent tab for the tab.
func setPinned(Bool, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to set the pinned state of the tab.
func setReaderModeActive(Bool, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to set the reader mode for the tab.
func setSelected(Bool, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to set the selected state of the tab.
func setZoomFactor(Double, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to set the zoom factor of the tab.
func shouldBypassPermissions(for: WKWebExtensionContext) -> Bool
Called to determine if the tab should bypass host permission checks.
func shouldGrantPermissionsOnUserGesture(for: WKWebExtensionContext) -> Bool
Called to determine if permissions should be granted for the tab on user gesture.
func size(for: WKWebExtensionContext) -> CGSize
Called when the size of the tab is needed.
func takeSnapshot(using: WKSnapshotConfiguration, for: WKWebExtensionContext, completionHandler: (UIImage?, (any Error)?) -> Void)
Called to capture a snapshot of the current webpage as an image.
func title(for: WKWebExtensionContext) -> String?
Called when the title of the tab is needed.
func url(for: WKWebExtensionContext) -> URL?
Called when the URL of the tab is needed.
func webView(for: WKWebExtensionContext) -> WKWebView?
Called when the web view for the tab is needed.
func window(for: WKWebExtensionContext) -> (any WKWebExtensionWindow)?
Called when the window containing the tab is needed.
func zoomFactor(for: WKWebExtensionContext) -> Double
Called when the zoom factor of the tab is needed.
Relationships
Inherits From
*         NSObjectProtocol
See Also
Web extensions
class WKWebExtension
An object that encapsulates a web extension’s resources that the manifest file defines.
protocol WKWebExtensionWindow
A protocol with methods that represent a window to web extensions.
class WKWebExtensionContext
An object that represents the runtime environment for a web extension.
class WKWebExtensionController
An object that manages a set of loaded extension contexts.
protocol WKWebExtensionControllerDelegate
A group of methods you use to customize web extension interactions.
Current page is WKWebExtensionTab
        WebKit WKWebExtensionWindow
Protocol
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
func activeTab(for: WKWebExtensionContext) -> (any WKWebExtensionTab)?
Called when the active tab is needed for the window.
func close(for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to close the window.
func focus(for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to focus the window.
func frame(for: WKWebExtensionContext) -> CGRect
Called when the frame of the window is needed.
func isPrivate(for: WKWebExtensionContext) -> Bool
Called when the private state of the window is needed.
func screenFrame(for: WKWebExtensionContext) -> CGRect
Called when the screen frame containing the window is needed.
func setFrame(CGRect, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to set the frame of the window.
func setWindowState(WKWebExtension.WindowState, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called to set the state of the window.
func tabs(for: WKWebExtensionContext) -> [any WKWebExtensionTab]
Called when the tabs are needed for the window.
func windowState(for: WKWebExtensionContext) -> WKWebExtension.WindowState
Called when the state of the window is needed.
func windowType(for: WKWebExtensionContext) -> WKWebExtension.WindowType
Called when the type of the window is needed.
Relationships
Inherits From
*         NSObjectProtocol
See Also
Web extensions
class WKWebExtension
An object that encapsulates a web extension’s resources that the manifest file defines.
protocol WKWebExtensionTab
A protocol with methods that represent a tab to web extensions.
class WKWebExtensionContext
An object that represents the runtime environment for a web extension.
class WKWebExtensionController
An object that manages a set of loaded extension contexts.
protocol WKWebExtensionControllerDelegate
A group of methods you use to customize web extension interactions.
Current page is WKWebExtensionWindow
       WebKit WKWebExtensionContext
Class
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
This class provides methods for managing the extension’s permissions, allowing it to inject content, run background logic, show popovers, and display other web-based UI to the user.
Topics
Enumerations
enum PermissionStatus
Constants used to indicate permission status in web extension context.
Structures
struct Error
Constants used to indicate errors in the web extension context domain.
struct NotificationUserInfoKey
Constants for specifying web extension context information in notifications.
Initializers
init(for: WKWebExtension)
Returns a web extension context initialized with a specified extension.
Instance Properties
var baseURL: URL
The base URL the context uses for loading extension resources or injecting content into webpages.
var commands: [WKWebExtension.Command]
The commands associated with the extension.
var currentPermissionMatchPatterns: Set<WKWebExtension.MatchPattern>
The currently granted permission match patterns that have not expired.
var currentPermissions: Set<WKWebExtension.Permission>
The currently granted permissions that have not expired.
var deniedPermissionMatchPatterns: [WKWebExtension.MatchPattern : Date]
The currently denied permission match patterns and their expiration dates.
var deniedPermissions: [WKWebExtension.Permission : Date]
The currently denied permissions and their expiration dates.
var errors: [any Error]
All errors that occurred in the extension context.
var focusedWindow: (any WKWebExtensionWindow)?
The window that currently has focus for this extension.
var grantedPermissionMatchPatterns: [WKWebExtension.MatchPattern : Date]
The currently granted permission match patterns and their expiration dates.
var grantedPermissions: [WKWebExtension.Permission : Date]
The currently granted permissions and their expiration dates.
var hasAccessToAllHosts: Bool
A Boolean value indicating if the currently granted permission match patterns set contains the <all_urls> pattern or any * host patterns.
var hasAccessToAllURLs: Bool
A Boolean value indicating if the currently granted permission match patterns set contains the <all_urls> pattern.
var hasAccessToPrivateData: Bool
A Boolean value indicating if the extension has access to private data.
var hasContentModificationRules: Bool
A boolean value indicating whether the extension includes rules used for content modification or blocking.
var hasInjectedContent: Bool
A Boolean value indicating whether the extension has script or stylesheet content that can be injected into webpages.
var hasRequestedOptionalAccessToAllHosts: Bool
A Boolean value indicating if the extension has requested optional access to all hosts.
var inspectionName: String?
The name shown when inspecting the background web view.
var isInspectable: Bool
Determines whether Web Inspector can inspect the WKWebView instances for this context.
var isLoaded: Bool
A Boolean value indicating if this context is loaded in an extension controller.
var openTabs: Set<AnyHashable>
A set of open tabs in all open windows that are exposed to this extension.
var openWindows: [any WKWebExtensionWindow]
The open windows that are exposed to this extension.
var optionsPageURL: URL?
The URL of the extension’s options page, if the extension has one.
var overrideNewTabPageURL: URL?
The URL to use as an alternative to the default new tab page, if the extension has one.
var uniqueIdentifier: String
A unique identifier used to distinguish the extension from other extensions and target it for messages.
var unsupportedAPIs: Set<String>!
Specifies unsupported APIs for this extension, making them undefined in JavaScript.
var webExtension: WKWebExtension
The extension this context represents.
var webExtensionController: WKWebExtensionController?
The extension controller this context is loaded in, otherwise nil if it isn’t loaded.
var webViewConfiguration: WKWebViewConfiguration?
The web view configuration to use for web views that load pages from this extension.
Instance Methods
func action(for: (any WKWebExtensionTab)?) -> WKWebExtension.Action?
Retrieves the extension action for a given tab, or the default action if nil is passed.
func clearUserGesture(in: any WKWebExtensionTab)
Called by the app to clear a user gesture in a specific tab.
func command(for: NSEvent) -> WKWebExtension.Command?
Retrieves the command associated with the given event without performing it.
func didActivateTab(any WKWebExtensionTab, previousActiveTab: (any WKWebExtensionTab)?)
Called by the app when a tab is activated to notify only this specific extension.
func didChangeTabProperties(WKWebExtension.TabChangedProperties, for: any WKWebExtensionTab)
Called by the app when the properties of a tab are changed to fire appropriate events with only this extension.
func didCloseTab(any WKWebExtensionTab, windowIsClosing: Bool)
Called by the app when a tab is closed to fire appropriate events with only this extension.
func didCloseWindow(any WKWebExtensionWindow)
Called by the app when a window is closed to fire appropriate events with only this extension.
func didDeselectTabs([any WKWebExtensionTab])
Called by the app when tabs are deselected to fire appropriate events with only this extension.
func didFocusWindow((any WKWebExtensionWindow)?)
Called by the app when a window gains focus to fire appropriate events with only this extension.
func didMoveTab(any WKWebExtensionTab, from: Int, in: (any WKWebExtensionWindow)?)
Called by the app when a tab is moved to fire appropriate events with only this extension.
func didOpenTab(any WKWebExtensionTab)
Called by the app when a new tab is opened to fire appropriate events with only this extension.
func didOpenWindow(any WKWebExtensionWindow)
Called by the app when a new window is opened to fire appropriate events with only this extension.
func didReplaceTab(any WKWebExtensionTab, with: any WKWebExtensionTab)
Called by the app when a tab is replaced by another tab to fire appropriate events with only this extension.
func didSelectTabs([any WKWebExtensionTab])
Called by the app when tabs are selected to fire appropriate events with only this extension.
func hasAccess(to: URL) -> Bool
Checks the specified URL against the currently granted permission match patterns.
func hasAccess(to: URL, in: (any WKWebExtensionTab)?) -> Bool
Checks the specified URL against the currently granted permission match patterns in a specific tab.
func hasActiveUserGesture(in: any WKWebExtensionTab) -> Bool
Indicates if a user gesture is currently active in the specified tab.
func hasInjectedContent(for: URL) -> Bool
Checks if the extension has script or stylesheet content that can be injected into the specified URL.
func hasPermission(WKWebExtension.Permission) -> Bool
Checks the specified permission against the currently granted permissions.
func hasPermission(WKWebExtension.Permission, in: (any WKWebExtensionTab)?) -> Bool
Checks the specified permission against the currently granted permissions in a specific tab.
func loadBackgroundContent(completionHandler: ((any Error)?) -> Void)
Loads the background content if needed for the extension.
func menuItems(for: any WKWebExtensionTab) -> [UIMenuElement]
Retrieves the menu items for a given tab.
func performAction(for: (any WKWebExtensionTab)?)
Performs the extension action associated with the specified tab or performs the default action if nil is passed.
func performCommand(WKWebExtension.Command)
Performs the specified command, triggering events specific to this extension.
func performCommand(for: UIKeyCommand) -> Bool
Performs the command associated with the given key command.
func performCommand(for: NSEvent) -> Bool
Performs the command associated with the given event.
func permissionStatus(for: WKWebExtension.Permission) -> WKWebExtensionContext.PermissionStatus
Checks the specified permission against the currently denied, granted, and requested permissions.
func permissionStatus(for: WKWebExtension.MatchPattern) -> WKWebExtensionContext.PermissionStatus
Checks the specified match pattern against the currently denied, granted, and requested permission match patterns.
func permissionStatus(for: URL) -> WKWebExtensionContext.PermissionStatus
Checks the specified URL against the currently denied, granted, and requested permission match patterns.
func permissionStatus(for: WKWebExtension.Permission, in: (any WKWebExtensionTab)?) -> WKWebExtensionContext.PermissionStatus
Checks the specified permission against the currently denied, granted, and requested permissions.
func permissionStatus(for: URL, in: (any WKWebExtensionTab)?) -> WKWebExtensionContext.PermissionStatus
Checks the specified URL against the currently denied, granted, and requested permission match patterns.
func permissionStatus(for: WKWebExtension.MatchPattern, in: (any WKWebExtensionTab)?) -> WKWebExtensionContext.PermissionStatus
Checks the specified match pattern against the currently denied, granted, and requested permission match patterns.
func setPermissionStatus(WKWebExtensionContext.PermissionStatus, for: WKWebExtension.Permission)
Sets the status of a permission with a distant future expiration date.
func setPermissionStatus(WKWebExtensionContext.PermissionStatus, for: URL)
Sets the permission status of a URL with a distant future expiration date.
func setPermissionStatus(WKWebExtensionContext.PermissionStatus, for: WKWebExtension.MatchPattern)
Sets the status of a match pattern with a distant future expiration date.
func setPermissionStatus(WKWebExtensionContext.PermissionStatus, for: URL, expirationDate: Date?)
Sets the permission status of a URL with a distant future expiration date.
func setPermissionStatus(WKWebExtensionContext.PermissionStatus, for: WKWebExtension.Permission, expirationDate: Date?)
Sets the status of a permission with a specific expiration date.
func setPermissionStatus(WKWebExtensionContext.PermissionStatus, for: WKWebExtension.MatchPattern, expirationDate: Date?)
Sets the status of a match pattern with a specific expiration date.
func userGesturePerformed(in: any WKWebExtensionTab)
Should be called by the app when a user gesture is performed in a specific tab.
Relationships
Inherits From
*         NSObject
Conforms To
*         CVarArg
*         CustomDebugStringConvertible
*         CustomStringConvertible
*         Equatable
*         Hashable
*         NSObjectProtocol
*         Sendable
See Also
Web extensions
class WKWebExtension
An object that encapsulates a web extension’s resources that the manifest file defines.
protocol WKWebExtensionTab
A protocol with methods that represent a tab to web extensions.
protocol WKWebExtensionWindow
A protocol with methods that represent a window to web extensions.
class WKWebExtensionController
An object that manages a set of loaded extension contexts.
protocol WKWebExtensionControllerDelegate
A group of methods you use to customize web extension interactions.
Current page is WKWebExtensionContext
       WebKit WKWebExtensionController
Class
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
You can have one or more extension controller instances, allowing different parts of the app to use different sets of extensions.
You can associate a controller with WKWebView using the webExtensionController property on WKWebViewConfiguration.
Topics
Initializers
init()
Returns a web extension controller initialized with the default configuration.
init(configuration: WKWebExtensionController.Configuration)
Returns a web extension controller initialized with the specified configuration.
Instance Properties
var configuration: WKWebExtensionController.Configuration
A copy of the configuration with which the web extension controller was initialized.
var delegate: (any WKWebExtensionControllerDelegate)?
The extension controller delegate.
var extensionContexts: Set<WKWebExtensionContext>
A set of all the currently loaded extension contexts.
var extensions: Set<WKWebExtension>
A set of all the currently loaded extensions.
Instance Methods
func didActivateTab(any WKWebExtensionTab, previousActiveTab: (any WKWebExtensionTab)?)
Should be called by the app when a tab is activated to notify all loaded web extensions.
func didChangeTabProperties(WKWebExtension.TabChangedProperties, for: any WKWebExtensionTab)
Should be called by the app when the properties of a tab are changed to fire appropriate events with all loaded web extensions.
func didCloseTab(any WKWebExtensionTab, windowIsClosing: Bool)
Should be called by the app when a tab is closed to fire appropriate events with all loaded web extensions.
func didCloseWindow(any WKWebExtensionWindow)
Should be called by the app when a window is closed to fire appropriate events with all loaded web extensions.
func didDeselectTabs([any WKWebExtensionTab])
Should be called by the app when tabs are deselected to fire appropriate events with all loaded web extensions.
func didFocusWindow((any WKWebExtensionWindow)?)
Should be called by the app when a window gains focus to fire appropriate events with all loaded web extensions.
func didMoveTab(any WKWebExtensionTab, from: Int, in: (any WKWebExtensionWindow)?)
Should be called by the app when a tab is moved to fire appropriate events with all loaded web extensions.
func didOpenTab(any WKWebExtensionTab)
Should be called by the app when a new tab is opened to fire appropriate events with all loaded web extensions.
func didOpenWindow(any WKWebExtensionWindow)
Should be called by the app when a new window is opened to fire appropriate events with all loaded web extensions.
func didReplaceTab(any WKWebExtensionTab, with: any WKWebExtensionTab)
Should be called by the app when a tab is replaced by another tab to fire appropriate events with all loaded web extensions.
func didSelectTabs([any WKWebExtensionTab])
Should be called by the app when tabs are selected to fire appropriate events with all loaded web extensions.
func extensionContext(for: URL) -> WKWebExtensionContext?
Returns a loaded extension context matching the specified URL.
func extensionContext(for: WKWebExtension) -> WKWebExtensionContext?
Returns a loaded extension context for the specified extension.
func fetchDataRecord(ofTypes: Set<WKWebExtension.DataType>, for: WKWebExtensionContext, completionHandler: (WKWebExtension.DataRecord?) -> Void)
Fetches a data record containing the given extension data types for a specific known web extension context.
func fetchDataRecords(ofTypes: Set<WKWebExtension.DataType>, completionHandler: ([WKWebExtension.DataRecord]) -> Void)
Fetches data records containing the given extension data types for all known extensions.
func load(WKWebExtensionContext) throws
Loads the specified extension context.
func removeData(ofTypes: Set<WKWebExtension.DataType>, from: [WKWebExtension.DataRecord], completionHandler: () -> Void)
Removes extension data of the given types for the given data records.
func unload(WKWebExtensionContext) throws
Unloads the specified extension context.
Type Properties
class var allExtensionDataTypes: Set<WKWebExtension.DataType>
Returns a set of all available extension data types.
Relationships
Inherits From
*         NSObject
Conforms To
*         CVarArg
*         CustomDebugStringConvertible
*         CustomStringConvertible
*         Equatable
*         Hashable
*         NSObjectProtocol
*         Sendable
See Also
Web extensions
class WKWebExtension
An object that encapsulates a web extension’s resources that the manifest file defines.
protocol WKWebExtensionTab
A protocol with methods that represent a tab to web extensions.
protocol WKWebExtensionWindow
A protocol with methods that represent a window to web extensions.
class WKWebExtensionContext
An object that represents the runtime environment for a web extension.
protocol WKWebExtensionControllerDelegate
A group of methods you use to customize web extension interactions.
Current page is WKWebExtensionController
        WebKit WKWebExtensionControllerDelegate
Protocol
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
func webExtensionController(WKWebExtensionController, connectUsing: WKWebExtension.MessagePort, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called when an extension context wants to establish a persistent connection to an application.
func webExtensionController(WKWebExtensionController, didUpdate: WKWebExtension.Action, forExtensionContext: WKWebExtensionContext)
Called when an action’s properties are updated.
func webExtensionController(WKWebExtensionController, focusedWindowFor: WKWebExtensionContext) -> (any WKWebExtensionWindow)?
Called when an extension context requests the currently focused window.
func webExtensionController(WKWebExtensionController, openNewTabUsing: WKWebExtension.TabConfiguration, for: WKWebExtensionContext, completionHandler: ((any WKWebExtensionTab)?, (any Error)?) -> Void)
Called when an extension context requests a new tab to be opened.
func webExtensionController(WKWebExtensionController, openNewWindowUsing: WKWebExtension.WindowConfiguration, for: WKWebExtensionContext, completionHandler: ((any WKWebExtensionWindow)?, (any Error)?) -> Void)
Called when an extension context requests a new window to be opened.
func webExtensionController(WKWebExtensionController, openOptionsPageFor: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called when an extension context requests its options page to be opened.
func webExtensionController(WKWebExtensionController, openWindowsFor: WKWebExtensionContext) -> [any WKWebExtensionWindow]
Called when an extension context requests the list of ordered open windows.
func webExtensionController(WKWebExtensionController, presentActionPopup: WKWebExtension.Action, for: WKWebExtensionContext, completionHandler: ((any Error)?) -> Void)
Called when a popup is requested to be displayed for a specific action.
func webExtensionController(WKWebExtensionController, promptForPermissionMatchPatterns: Set<WKWebExtension.MatchPattern>, in: (any WKWebExtensionTab)?, for: WKWebExtensionContext, completionHandler: (Set<WKWebExtension.MatchPattern>, Date?) -> Void)
Called when an extension context requests access to a set of match patterns.
func webExtensionController(WKWebExtensionController, promptForPermissionToAccess: Set<URL>, in: (any WKWebExtensionTab)?, for: WKWebExtensionContext, completionHandler: (Set<URL>, Date?) -> Void)
Called when an extension context requests access to a set of URLs.
func webExtensionController(WKWebExtensionController, promptForPermissions: Set<WKWebExtension.Permission>, in: (any WKWebExtensionTab)?, for: WKWebExtensionContext, completionHandler: (Set<WKWebExtension.Permission>, Date?) -> Void)
Called when an extension context requests permissions.
func webExtensionController(WKWebExtensionController, sendMessage: Any, toApplicationWithIdentifier: String?, for: WKWebExtensionContext, replyHandler: (Any?, (any Error)?) -> Void)
Called when an extension context wants to send a one-time message to an application.
Relationships
Inherits From
*         NSObjectProtocol
See Also
Web extensions
class WKWebExtension
An object that encapsulates a web extension’s resources that the manifest file defines.
protocol WKWebExtensionTab
A protocol with methods that represent a tab to web extensions.
protocol WKWebExtensionWindow
A protocol with methods that represent a window to web extensions.
class WKWebExtensionContext
An object that represents the runtime environment for a web extension.
class WKWebExtensionController
An object that manages a set of loaded extension contexts.
Current page is WKWebExtensionControllerDelegate
   
