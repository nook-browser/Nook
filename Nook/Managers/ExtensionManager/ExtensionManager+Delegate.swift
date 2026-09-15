//
//  ExtensionManager+Delegate.swift
//  Nook
//
//  WKWebExtensionControllerDelegate methods extracted from ExtensionManager.
//

import AppKit
import Foundation
import NookTabsCore
import os
import SwiftData
import SwiftUI
import WebKit

extension ExtensionManager {

    // MARK: - WKWebExtensionControllerDelegate

    func webExtensionController(
        _ controller: WKWebExtensionController,
        presentActionPopup action: WKWebExtension.Action,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let extName = extensionContext.webExtension.displayName ?? "?"
        Self.logger.info("presentActionPopup for '\(extName, privacy: .public)'")

        // Permissions were granted when the context loaded. Optional permissions stay
        // behind chrome.permissions.request(); opening a popup does not grant them.

        guard let popover = action.popupPopover else {
            Self.logger.error("No popover available on action for '\(extName, privacy: .public)'")
            completionHandler(
                NSError(
                    domain: "ExtensionManager",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "No popover available"
                    ]
                )
            )
            return
        }

        popover.behavior = .transient

        if let webView = action.popupWebView {
            webView.isInspectable = true
            // Only set uiDelegate — do NOT override navigationDelegate as Apple's
            // WKWebExtension framework uses its own internal delegate to load
            // webkit-extension:// URLs. Overriding it breaks popup loading.
            let delegate = PopupUIDelegate(webView: webView)
            self.popupUIDelegate = delegate
            webView.uiDelegate = delegate

            // Install clipboard bridge for extension popups (e.g. Bitwarden copy button).
            // WebKit's Clipboard API is restricted in third-party WKWebView apps, so we
            // polyfill navigator.clipboard.writeText() via a native message handler.
            PopupClipboardHandler.install(on: webView, retainedBy: self)

            Self.logger.debug("Popup webView: URL=\(webView.url?.absoluteString ?? "nil", privacy: .public), isLoading=\(webView.isLoading)")

            // No reload here. WebKit calls this delegate after the popup has finished loading, in a
            // fresh webview on every open (verified in a WKWebExtensionController harness), so the
            // old reload-if-not-loading branch reloaded every popup a second time.
        } else {
            Self.logger.warning("No popupWebView on action for '\(extName, privacy: .public)'")
        }

        // Present the popover on main thread
        let popupWebView = action.popupWebView
        DispatchQueue.main.async {
            let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow

            popover.behavior = .transient
            popover.delegate = self
            self.isPopupActive = true

            // After showing the popover, make the popup webview first responder
            // so Cmd+C and other keyboard shortcuts are routed to it.
            let focusPopupWebView = {
                if let webView = popupWebView,
                   let popoverWindow = webView.window {
                    popoverWindow.makeFirstResponder(webView)
                }
            }

            // Keep popover size fixed; no autosizing bookkeeping

            // Try to use registered anchor for this extension
            if let extId = self.extensionContexts.first(where: {
                $0.value === extensionContext
            })?.key,
                var anchors = self.actionAnchors[extId]
            {
                Self.logger.debug("   📌 Registered anchors for this extension: \(anchors.count)")

                // Clean up stale anchors (no view OR no window)
                anchors.removeAll { $0.view == nil || $0.view?.window == nil }
                self.actionAnchors[extId] = anchors
                Self.logger.debug("   📌 After cleanup: \(anchors.count) anchors")

                // Find anchor in current window
                if let win = targetWindow,
                    let match = anchors.first(where: { $0.window === win }),
                    let view = match.view,
                    view.window != nil  // Double-check view is still in window
                {
                    popover.show(
                        relativeTo: view.bounds,
                        of: view,
                        preferredEdge: .maxY
                    )
                    focusPopupWebView()
                    completionHandler(nil)
                    return
                }

                // Use first available anchor that's still in a window
                if let validAnchor = anchors.first(where: { $0.view?.window != nil }),
                   let view = validAnchor.view
                {
                    popover.show(
                        relativeTo: view.bounds,
                        of: view,
                        preferredEdge: .maxY
                    )
                    focusPopupWebView()
                    completionHandler(nil)
                    return
                }

                Self.logger.debug("   ⚠️  No valid anchors found (all were removed from windows)")
            }

            // Fallback to center of window
            if let window = targetWindow, let contentView = window.contentView {
                let rect = CGRect(
                    x: contentView.bounds.midX - 10,
                    y: contentView.bounds.maxY - 50,
                    width: 20,
                    height: 20
                )
                popover.show(
                    relativeTo: rect,
                    of: contentView,
                    preferredEdge: .minY
                )
                focusPopupWebView()
                completionHandler(nil)
                return
            }

            Self.logger.error("DELEGATE: No anchor or contentView available")
            completionHandler(
                NSError(
                    domain: "ExtensionManager",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "No window available"]
                )
            )
        }
    }

    // MARK: - Windows exposure (tabs/windows APIs)

    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        // nil while a private window is focused.
        browserManagerRef?.windowRegistry?.activeWindow.flatMap { windowAdapter(for: $0) }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        openWindowAdapters
    }

    // MARK: - Permission prompting helper (invoked by delegate when needed)
    func presentPermissionPrompt(
        requestedPermissions: Set<WKWebExtension.Permission>,
        optionalPermissions: Set<WKWebExtension.Permission>,
        requestedMatches: Set<WKWebExtension.MatchPattern>,
        optionalMatches: Set<WKWebExtension.MatchPattern>,
        extensionDisplayName: String,
        isRuntimeRequest: Bool = false,
        onDecision:
            @escaping (
                _ grantedPermissions: Set<WKWebExtension.Permission>,
                _ grantedMatches: Set<WKWebExtension.MatchPattern>
            ) -> Void,
        onCancel: @escaping () -> Void,
        extensionLogo: NSImage
    ) {
        guard let bm = browserManagerRef else {
            onCancel()
            return
        }

        // Convert enums to readable strings for UI
        let reqPerms = requestedPermissions.map(\.rawValue).sorted()
        let optPerms = optionalPermissions.map(\.rawValue).sorted()
        let reqHosts = requestedMatches.map(\.string).sorted()
        let optHosts = optionalMatches.map(\.string).sorted()

        bm.showDialog {
            StandardDialog(
                header: {
                    EmptyView()
                },
                content: {
                    ExtensionPermissionView(
                        extensionName: extensionDisplayName,
                        requestedPermissions: reqPerms,
                        optionalPermissions: optPerms,
                        requestedHostPermissions: reqHosts,
                        optionalHostPermissions: optHosts,
                        isRuntimeRequest: isRuntimeRequest,
                        onGrant: {
                            let allPerms = requestedPermissions.union(
                                optionalPermissions
                            )
                            let allHosts = requestedMatches.union(
                                optionalMatches
                            )
                            bm.closeDialog()
                            onDecision(allPerms, allHosts)
                        },
                        onDeny: {
                            bm.closeDialog()
                            onCancel()
                        },
                        extensionLogo: extensionLogo
                    )
                },
                footer: { EmptyView() }
            )
        }
    }

    // Delegate entry point for permission requests from extensions at runtime
    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler:
            @escaping (Set<WKWebExtension.Permission>, Date?) -> Void
    ) {
        let displayName =
            extensionContext.webExtension.displayName ?? "Extension"
        presentPermissionPrompt(
            requestedPermissions: permissions,
            optionalPermissions: [],
            requestedMatches: [],
            optionalMatches: [],
            extensionDisplayName: displayName,
            isRuntimeRequest: true,
            onDecision: { [weak self] grantedPerms, _ in
                for p in permissions {
                    extensionContext.setPermissionStatus(
                        grantedPerms.contains(p)
                            ? .grantedExplicitly : .deniedExplicitly,
                        for: p
                    )
                }
                completionHandler(grantedPerms, nil)
                self?.persistGrantedOptionalPermissions(
                    for: extensionContext,
                    permissions: grantedPerms
                )
            },
            onCancel: {
                for p in permissions {
                    extensionContext.setPermissionStatus(
                        .deniedExplicitly,
                        for: p
                    )
                }
                completionHandler([], nil)
            },
            extensionLogo: extensionContext.webExtension.icon(
                for: .init(width: 64, height: 64)
            ) ?? NSImage()
        )
    }

    // MARK: - Persist runtime-granted optional permissions

    /// Save granted optional permissions to the ExtensionEntity so they survive app restarts.
    private func persistGrantedOptionalPermissions(
        for extensionContext: WKWebExtensionContext,
        permissions: Set<WKWebExtension.Permission> = [],
        matchPatterns: Set<WKWebExtension.MatchPattern> = []
    ) {
        let extensionId = extensionContext.uniqueIdentifier
        let predicate = #Predicate<ExtensionEntity> { $0.id == extensionId }
        guard let entity = try? context.fetch(
            FetchDescriptor<ExtensionEntity>(predicate: predicate)
        ).first else { return }

        // Merge new grants with existing ones
        let newPerms = permissions.map { String(describing: $0) }
        let existingPerms = Set(entity.grantedOptionalPermissions ?? [])
        entity.grantedOptionalPermissions = Array(existingPerms.union(newPerms))

        let newMatches = matchPatterns.map { String(describing: $0) }
        let existingMatches = Set(entity.grantedOptionalMatchPatterns ?? [])
        entity.grantedOptionalMatchPatterns = Array(existingMatches.union(newMatches))

        try? context.save()
    }

    // MARK: - Opening tabs/windows requested by extensions

    /// The regular window an extension request targets: the window it names, else the focused
    /// regular window, else any regular window.
    private func targetWindow(_ requested: (any WKWebExtensionWindow)?) -> BrowserWindowState? {
        if let adapter = requested as? ExtensionWindowAdapter, let state = adapter.state { return state }
        guard let registry = browserManagerRef?.windowRegistry else { return nil }
        if let active = registry.activeWindow, windowAdapter(for: active) != nil { return active }
        return registry.allWindows.first { windowAdapter(for: $0) != nil }
    }

    private static func noWindowError() -> NSError {
        NSError(domain: "ExtensionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No browser window available"])
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler:
            @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        guard let bm = browserManagerRef, let window = targetWindow(configuration.window),
              let spaceID = window.spaceID
        else {
            completionHandler(nil, Self.noWindowError())
            return
        }
        let url = configuration.url ?? TabsController.homeURL
        let parent: Parent? = configuration.shouldBePinned ? .pinned(spaceID: spaceID) : nil
        guard let itemID = bm.tabs.open(
            url: url, in: window, placement: configuration.shouldBeActive ? .newTab : .background, parent: parent)
        else {
            completionHandler(nil, NSError(domain: "ExtensionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not open tab"]))
            return
        }

        // Extension pages (options, popup) load with the extension's configuration.
        if let scheme = url.scheme?.lowercased(), scheme == "safari-web-extension" || scheme == "webkit-extension",
           let resolvedContext = controller.extensionContext(for: url),
           let session = bm.tabs.session(for: itemID) {
            session.applyConfigurationOverride(
                resolvedContext.webViewConfiguration ?? BrowserConfiguration.shared.webViewConfiguration)
        }
        if configuration.shouldBeMuted { bm.tabs.session(for: itemID)?.setMuted(true) }
        Self.logger.info("Extension opened tab \(url.absoluteString, privacy: .public)")
        completionHandler(adapter(for: itemID), nil)
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler:
            @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        guard let bm = browserManagerRef, let window = targetWindow(nil) else {
            completionHandler(nil, Self.noWindowError())
            return
        }
        let tabs = bm.tabs

        // OAuth flows from extensions open as a tab so they share the page's data store;
        // mini windows use separate stores, which breaks the flow.
        if let firstURL = configuration.tabURLs.first, OAuthDetector.isLikelyOAuthPopupURL(firstURL) {
            tabs.open(url: firstURL, in: window, placement: .newTab)
            completionHandler(windowAdapter(for: window), nil)
            return
        }

        // An extension window is emulated as a new space in the focused window.
        guard let profileID = window.profileID ?? window.spaceID.flatMap({ tabs.space($0)?.profileID }),
              let spaceID = tabs.createSpace(profileID: profileID, name: "Window", icon: "macwindow",
                                             accentHex: "#7C7C7C", after: window.spaceID)
        else {
            completionHandler(nil, NSError(domain: "ExtensionManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create window"]))
            return
        }
        tabs.setSpace(spaceID, in: window)
        let urls = configuration.tabURLs.isEmpty ? [TabsController.homeURL] : configuration.tabURLs
        // Each tab opens at the top, so open in reverse and select the first URL last.
        for url in urls.dropFirst().reversed() {
            tabs.open(url: url, in: window, placement: .background)
        }
        tabs.open(url: urls[0], in: window, placement: .newTab)
        Self.logger.info("Extension opened window as space with \(urls.count) tabs")
        completionHandler(windowAdapter(for: window), nil)
    }

    // MARK: - Native Messaging Support

    func webExtensionController(
        _ controller: WKWebExtensionController,
        sendMessage message: Any,
        toApplicationWithIdentifier applicationId: String?,
        for extensionContext: WKWebExtensionContext,
        replyHandler: @escaping (Any?, (any Error)?) -> Void
    ) {
        // Intercept Safari-specific native messages that we can handle natively.
        // Bitwarden's Safari extension sends commands via native messaging instead of
        // using web clipboard APIs.
        if let msg = message as? [String: Any],
           let command = msg["command"] as? String {

            switch command {
            case "showPopover":
                // When isSafariApi=true and chrome.browserAction.openPopup() is unavailable,
                // Bitwarden sends this to open its action popup.
                Self.logger.info("[NativeMessaging] Intercepting showPopover for '\(extensionContext.webExtension.displayName ?? "?", privacy: .public)'")
                let session = browserManagerRef?.tabs.activeWindowSession
                extensionContext.performAction(for: session.flatMap { adapter(for: $0.itemID) })
                replyHandler(["success": true], nil)
                return

            case "copyToClipboard":
                // Bitwarden Safari sends clipboard writes via native messaging.
                guard declaresPermission("clipboardWrite", in: extensionContext) else {
                    replyHandler(["success": false, "error": "clipboardWrite permission required"], nil)
                    return
                }
                let text = msg["text"] as? String ?? msg["data"] as? String ?? ""
                if !text.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                replyHandler(["success": true], nil)
                return

            case "readFromClipboard":
                // Same rule as Chrome: reading the clipboard requires the clipboardRead permission.
                guard declaresPermission("clipboardRead", in: extensionContext) else {
                    Self.logger.warning("[NativeMessaging] Denying clipboard read from '\(extensionContext.webExtension.displayName ?? "Unknown", privacy: .public)': clipboardRead not declared")
                    replyHandler(["text": "", "error": "Clipboard access denied"], nil)
                    return
                }
                let text = NSPasteboard.general.string(forType: .string) ?? ""
                replyHandler(["text": text], nil)
                return

            case "sleep":
                // Bitwarden Safari uses "sleep" as a long-poll for vault timeout detection.
                // The native host should block until a lock event, then respond.
                // We respond after a delay to prevent a tight polling loop.
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                    replyHandler(["command": "awake"] as [String: Any], nil)
                }
                return

            default:
                break
            }
        }

        guard let applicationId else {
            replyHandler(nil, NSError(domain: "NativeMessaging", code: 1, userInfo: [NSLocalizedDescriptionKey: "No application identifier"]))
            return
        }

        // Fast-path: if we already know this host is unavailable, return immediately
        // without launching a process or logging. Extensions like Bitwarden poll every
        // 500ms. Return a valid reply (not an error) so WebKit doesn't log a runtime error.
        let cacheKey = nativeHostCacheKey(applicationId, extensionContext)
        if unavailableNativeHosts.contains(cacheKey) {
            replyHandler(["command": "disconnected"] as [String: Any], nil)
            return
        }

        Self.logger.info("[NativeMessaging] sendMessage to '\(applicationId, privacy: .public)'")

        // Single-shot message handling
        let handler = NativeMessagingHandler(applicationId: applicationId, extensionContext: extensionContext)
        handler.sendMessage(message) { [weak self] response, error in
            // Cache only a missing or disallowed host; timeouts and bad replies may be transient.
            if let error = error as NSError?,
               error.domain == NativeMessagingHandler.errorDomain,
               error.code == NativeMessagingHandler.ErrorCode.hostNotFound.rawValue {
                self?.unavailableNativeHosts.insert(cacheKey)
                Self.logger.info("[NativeMessaging] Marked '\(applicationId, privacy: .public)' as unavailable for this extension")
            }
            replyHandler(response, error)
        }
    }

    func webExtensionController(
        _ controller: WKWebExtensionController,
        connectUsing port: WKWebExtension.MessagePort,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping ((any Error)?) -> Void
    ) {
        guard let applicationId = port.applicationIdentifier else {
            Self.logger.error("[NativeMessaging] Port connection missing application identifier")
            completionHandler(NSError(domain: "NativeMessaging", code: 1, userInfo: [NSLocalizedDescriptionKey: "No application identifier"]))
            return
        }

        // Fast-path: if we already know this host is unavailable, handle the port
        // internally. Safari extensions (e.g. Bitwarden .appex) call connectNative()
        // expecting the HOST APP to respond — not an external process. If we disconnect
        // the port, the extension retries immediately creating a CPU-burning loop.
        // Instead, keep the port alive and handle known commands (clipboard, popover).
        let cacheKey = nativeHostCacheKey(applicationId, extensionContext)
        if unavailableNativeHosts.contains(cacheKey) {
            Self.logger.debug("[NativeMessaging] Handling port internally for '\(applicationId, privacy: .public)' (no external host)")
            setupInternalPortHandler(port: port, extensionContext: extensionContext, applicationId: applicationId)
            completionHandler(nil)
            return
        }

        let handler = NativeMessagingHandler(applicationId: applicationId, extensionContext: extensionContext)
        // Keep the handler alive for the life of the conversation.
        nativeMessagingHandlers.append(handler)
        handler.onClose = { [weak self, weak handler] in
            self?.nativeMessagingHandlers.removeAll { $0 === handler }
        }
        handler.connect(port: port) { [weak self, weak handler] hostFound in
            guard let self, !hostFound else { return }
            self.nativeMessagingHandlers.removeAll { $0 === handler }
            self.unavailableNativeHosts.insert(cacheKey)
            Self.logger.info("[NativeMessaging] No allowed host '\(applicationId, privacy: .public)'; handling port in-process")
            // Keep the port alive so Safari extension commands (clipboard, popover) still work.
            self.setupInternalPortHandler(port: port, extensionContext: extensionContext, applicationId: applicationId)
        }
        completionHandler(nil)
    }

    /// Host availability depends on the calling extension (allowed_origins), so cache per pair.
    private func nativeHostCacheKey(_ applicationId: String, _ context: WKWebExtensionContext) -> String {
        "\(context.uniqueIdentifier)|\(applicationId)"
    }

    /// Whether the extension lists `permission` in its manifest `permissions`. Used for
    /// permissions WebKit does not model itself (clipboardRead).
    func declaresPermission(_ permission: String, in context: WKWebExtensionContext) -> Bool {
        (context.webExtension.manifest["permissions"] as? [String])?.contains(permission) == true
    }

    // MARK: - Internal Port Handler for Safari Extensions

    /// Handle a native messaging port internally when no external host is available.
    /// Safari extensions (.appex) expect their host app to respond on this channel.
    ///
    /// Routes messages through registered `InternalNativePortHandler` instances first
    /// (e.g. Bitwarden biometric handler), then falls back to generic command handling
    /// (clipboard, popover) that's common across many Safari extensions.
    private func setupInternalPortHandler(
        port: WKWebExtension.MessagePort,
        extensionContext: WKWebExtensionContext,
        applicationId: String? = nil
    ) {
        // Resolve a registered handler for this application identifier
        let registeredHandler: (any InternalNativePortHandler)? =
            applicationId.flatMap { internalHandler(for: $0) }

        // The handler is (message, error); earlier code read the error slot as the message.
        port.messageHandler = { [weak self] message, error in
            guard error == nil else { return }
            MainActor.assumeIsolated {
                guard let msg = message as? [String: Any] else {
                    // Unknown message format — ack to keep port alive
                    port.sendMessage(["command": "unknownCommand"] as [String: Any]) { _ in }
                    return
                }

                // Try the registered extension-specific handler first
                if let registeredHandler, registeredHandler.handleMessage(msg, port: port) {
                    return
                }

                // Fall through to generic Safari extension commands
                guard let command = msg["command"] as? String else {
                    port.sendMessage(["command": "unknownCommand"] as [String: Any]) { _ in }
                    return
                }

                switch command {
                case "copyToClipboard":
                    guard self?.declaresPermission("clipboardWrite", in: extensionContext) == true else {
                        port.sendMessage(["command": command, "success": false] as [String: Any]) { _ in }
                        return
                    }
                    let text = msg["text"] as? String ?? msg["data"] as? String ?? ""
                    if !text.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    port.sendMessage(["command": command, "success": true] as [String: Any]) { _ in }

                case "readFromClipboard":
                    guard self?.declaresPermission("clipboardRead", in: extensionContext) == true else {
                        port.sendMessage(["command": command, "text": "", "error": "Clipboard access denied"] as [String: Any]) { _ in }
                        return
                    }
                    let text = NSPasteboard.general.string(forType: .string) ?? ""
                    port.sendMessage(["command": command, "text": text] as [String: Any]) { _ in }

                case "showPopover":
                    let session = self?.browserManagerRef?.tabs.activeWindowSession
                    extensionContext.performAction(for: session.flatMap { self?.adapter(for: $0.itemID) })
                    port.sendMessage(["command": command, "success": true] as [String: Any]) { _ in }

                default:
                    Self.logger.debug("[NativeMessaging] Unhandled port command: \(command, privacy: .public)")
                    port.sendMessage(["command": command, "response": "not supported"] as [String: Any]) { _ in }
                }
            }
        }

        port.disconnectHandler = { _ in
            Self.logger.debug("[NativeMessaging] Internal port handler disconnected")
        }
    }

    // Open the extension's options page (inside a browser tab)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openOptionsPageFor extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let displayName =
            extensionContext.webExtension.displayName ?? "Extension"
        Self.logger.debug("   Extension: \(displayName)")

        // Resolve the options page URL. Prefer the SDK property when available.
        let sdkURL = extensionContext.optionsPageURL
        let manifestURL = self.computeOptionsPageURL(for: extensionContext)
        let kvcURL =
            (extensionContext as AnyObject).value(forKey: "optionsPageURL")
            as? URL
        let optionsURL: URL?
        if let u = sdkURL {
            optionsURL = u
        } else if let u = manifestURL {
            optionsURL = u
        } else if let u = kvcURL, u.scheme?.lowercased() != "file" {
            optionsURL = u
        } else if let u = kvcURL {
            optionsURL = u
        } else {
            optionsURL = nil
        }

        guard let optionsURL else {
            Self.logger.error("No options page URL found for extension")
            completionHandler(
                NSError(
                    domain: "ExtensionManager",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "No options page URL found for extension"
                    ]
                )
            )
            return
        }

        Self.logger.info("Opening options page: \(optionsURL.absoluteString)")

        // Create a dedicated WebView using the extension's webViewConfiguration so
        // the WebExtensions environment (browser/chrome APIs) is available.
        let config =
            extensionContext.webViewConfiguration
            ?? BrowserConfiguration.shared.webViewConfiguration
        // Ensure the controller is attached for safety
        if config.webExtensionController == nil, let c = extensionController {
            config.webExtensionController = c
        }
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        // No navigation delegate needed for options page

        // WebKit exposes both `browser` and `chrome` in extension pages; no alias script needed.

        // SECURITY FIX: Load the options page with restricted file access
        if optionsURL.isFileURL {
            // SECURITY FIX: Only allow access to the specific extension directory, not the entire package
            guard
                let extId = extensionContexts.first(where: {
                    $0.value === extensionContext
                })?.key,
                let inst = installedExtensions.first(where: { $0.id == extId })
            else {
                Self.logger.error("Could not resolve extension for secure file access")
                completionHandler(
                    NSError(
                        domain: "ExtensionManager",
                        code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Could not resolve extension for secure file access"
                        ]
                    )
                )
                return
            }

            // SECURITY FIX: Validate that the options URL is within the extension directory
            let extensionRoot = URL(
                fileURLWithPath: inst.packagePath,
                isDirectory: true
            )

            // SECURITY FIX: Normalize paths and resolve symlinks to prevent path traversal attacks
            let canonicalRoot = extensionRoot.resolvingSymlinksInPath().standardized.path
            let canonicalOptions = optionsURL.resolvingSymlinksInPath().standardized.path

            // Check if options URL is within the extension directory (prevent path traversal via symlinks)
            if !canonicalOptions.hasPrefix(canonicalRoot) {
                Self.logger.error("SECURITY: Options URL outside extension directory: \(canonicalOptions, privacy: .public) not in \(canonicalRoot, privacy: .public)")
                completionHandler(
                    NSError(
                        domain: "ExtensionManager",
                        code: 4,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Options URL outside extension directory"
                        ]
                    )
                )
                return
            }

            // SECURITY FIX: Additional validation - ensure no path traversal attempts
            let relativePath = String(
                canonicalOptions.dropFirst(canonicalRoot.count)
            )
            if relativePath.contains("..") || relativePath.hasPrefix("/") {
                Self.logger.error("SECURITY: Path traversal attempt detected: \(relativePath)")
                completionHandler(
                    NSError(
                        domain: "ExtensionManager",
                        code: 5,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Path traversal attempt detected"
                        ]
                    )
                )
                return
            }

            // SECURITY FIX: Only grant access to the extension's specific directory, not parent directories
            webView.loadFileURL(optionsURL, allowingReadAccessTo: extensionRoot)
        } else {
            // For non-file URLs (http/https), load normally
            webView.load(URLRequest(url: optionsURL))
        }

        // Present in a lightweight NSWindow to avoid coupling to Tab UI.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "\(displayName) – Options"

        let container = NSView(frame: window.contentView?.bounds ?? .zero)
        container.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = container

        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(
                equalTo: container.trailingAnchor
            ),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Keep window alive keyed by extension id
        if let extId = extensionContexts.first(where: {
            $0.value === extensionContext
        })?.key {
            optionsWindows[extId] = window
        }

        window.center()
        window.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }

    // Resolve options page URL from manifest as a fallback for SDKs that don't expose optionsPageURL
    private func computeOptionsPageURL(for context: WKWebExtensionContext)
        -> URL?
    {
        Self.logger.debug("   Extension: \(context.webExtension.displayName ?? "Unknown")")
        Self.logger.debug("   Unique ID: \(context.uniqueIdentifier)")

        // Try to map the context back to our InstalledExtension via dictionary identity
        if let extId = extensionContexts.first(where: { $0.value === context })?
            .key,
            let inst = installedExtensions.first(where: { $0.id == extId })
        {
            Self.logger.info("Found installed extension: \(inst.name)")

            // MV3/MV2: options_ui.page; MV2 legacy: options_page
            var pagePath: String?
            if let options = inst.manifest["options_ui"] as? [String: Any],
                let p = options["page"] as? String, !p.isEmpty
            {
                pagePath = p
                Self.logger.debug("   Found options_ui.page: \(p)")
            } else if let p = inst.manifest["options_page"] as? String,
                !p.isEmpty
            {
                pagePath = p
                Self.logger.debug("   Found options_page: \(p)")
            } else {

                // Fallback: Check for common options page paths
                let commonPaths = [
                    "ui/options/index.html",
                    "options/index.html",
                    "options.html",
                    "settings.html",
                ]

                for path in commonPaths {
                    let fullFilePath = URL(fileURLWithPath: inst.packagePath)
                        .appendingPathComponent(path)
                    if FileManager.default.fileExists(atPath: fullFilePath.path)
                    {
                        pagePath = path
                        Self.logger.info("Found options page at: \(path)")
                        break
                    }
                }
            }

            if let page = pagePath {
                // SECURITY: Reject paths containing ".." to prevent path traversal attacks
                if page.contains("..") {
                    Self.logger.error("[SECURITY] Path traversal detected in options page path: \(page, privacy: .public)")
                    return nil
                }

                // Build an extension-scheme URL using the context baseURL
                let extBase = context.baseURL
                let optionsURL = extBase.appendingPathComponent(page)
                Self.logger.info("Generated options extension URL: \(optionsURL.absoluteString)")
                return optionsURL
            } else {
                Self.logger.error("No options page found in manifest or common paths")
                Self.logger.debug("   Manifest keys: \(inst.manifest.keys.sorted())")
            }
        } else {
            Self.logger.error("Could not find installed extension for context")
        }
        return nil
    }
    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<
            WKWebExtension.MatchPattern
        >,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler:
            @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void
    ) {
        let displayName =
            extensionContext.webExtension.displayName ?? "Extension"
        presentPermissionPrompt(
            requestedPermissions: [],
            optionalPermissions: [],
            requestedMatches: matchPatterns,
            optionalMatches: [],
            extensionDisplayName: displayName,
            isRuntimeRequest: true,
            onDecision: { [weak self] _, grantedMatches in
                for m in matchPatterns {
                    extensionContext.setPermissionStatus(
                        grantedMatches.contains(m)
                            ? .grantedExplicitly : .deniedExplicitly,
                        for: m
                    )
                }
                completionHandler(grantedMatches, nil)
                self?.persistGrantedOptionalPermissions(
                    for: extensionContext,
                    matchPatterns: grantedMatches
                )
            },
            onCancel: {
                for m in matchPatterns {
                    extensionContext.setPermissionStatus(
                        .deniedExplicitly,
                        for: m
                    )
                }
                completionHandler([], nil)
            },
            extensionLogo: extensionContext.webExtension.icon(
                for: .init(width: 64, height: 64)
            ) ?? NSImage()
        )
    }

    // URL-specific access prompts (used for cross-origin network requests from extension contexts)
    // Auto-grant URLs that fall within the extension's already-granted host permissions.
    // Only prompt for URLs the extension has no declared permission for.
    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionToAccess urls: Set<URL>,
        in tab: (any WKWebExtensionTab)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Set<URL>, Date?) -> Void
    ) {
        // Check each URL against the extension's granted permissions
        var granted = Set<URL>()
        var needsPrompt = Set<URL>()

        for url in urls {
            let status = extensionContext.permissionStatus(for: url)
            if status == .grantedExplicitly || status == .grantedImplicitly {
                granted.insert(url)
            } else {
                needsPrompt.insert(url)
            }
        }

        // If all URLs are already covered by granted permissions, auto-approve
        if needsPrompt.isEmpty {
            completionHandler(granted, nil)
            return
        }

        // Prompt only for URLs not covered by existing permissions
        let displayName =
            extensionContext.webExtension.displayName ?? "Extension"

        guard let bm = browserManagerRef else {
            // No UI available — grant what we can, deny the rest
            completionHandler(granted, nil)
            return
        }

        let urlStrings = needsPrompt.map { $0.absoluteString }.sorted()

        bm.showDialog {
            StandardDialog(
                header: { EmptyView() },
                content: {
                    ExtensionPermissionView(
                        extensionName: displayName,
                        requestedPermissions: [],
                        optionalPermissions: [],
                        requestedHostPermissions: urlStrings,
                        optionalHostPermissions: [],
                        isRuntimeRequest: true,
                        onGrant: {
                            bm.closeDialog()
                            completionHandler(urls, nil)
                        },
                        onDeny: {
                            bm.closeDialog()
                            completionHandler(granted, nil)
                        },
                        extensionLogo: extensionContext.webExtension.icon(
                            for: .init(width: 64, height: 64)
                        ) ?? NSImage()
                    )
                },
                footer: { EmptyView() }
            )
        }
    }
}
