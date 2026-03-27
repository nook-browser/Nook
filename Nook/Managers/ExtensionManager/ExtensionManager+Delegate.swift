//
//  ExtensionManager+Delegate.swift
//  Nook
//
//  WKWebExtensionControllerDelegate methods extracted from ExtensionManager.
//

import AppKit
import Foundation
import os
import SwiftData
import SwiftUI
import WebKit

@available(macOS 15.4, *)
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

        // Grant ALL the extension's requested + optional permissions so the popup
        // can use chrome.tabs, chrome.runtime, etc. without hanging.
        // allRequestedMatchPatterns includes content_scripts patterns, not just host_permissions.
        for p in extensionContext.webExtension.requestedPermissions {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: p)
        }
        for p in extensionContext.webExtension.optionalPermissions {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: p)
        }
        for m in extensionContext.webExtension.allRequestedMatchPatterns {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: m)
        }
        for m in extensionContext.webExtension.optionalPermissionMatchPatterns {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: m)
        }

        Self.logger.debug("Granted \(extensionContext.currentPermissions.count) permissions for '\(extName, privacy: .public)'")

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

            // The popup webview is created by WKWebExtension with a URL set but not
            // always loading. Explicitly trigger the load to ensure the popup renders.
            if !webView.isLoading, let popupURL = webView.url {
                webView.load(URLRequest(url: popupURL))
            }
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

    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        focusedWindowFor extensionContext: WKWebExtensionContext
    ) -> (any WKWebExtensionWindow)? {
        guard let bm = browserManagerRef else {
            return nil
        }
        if windowAdapter == nil {
            windowAdapter = ExtensionWindowAdapter(browserManager: bm)
        }
        return windowAdapter
    }

    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openWindowsFor extensionContext: WKWebExtensionContext
    ) -> [any WKWebExtensionWindow] {
        guard let bm = browserManagerRef else {
            return []
        }
        if windowAdapter == nil {
            windowAdapter = ExtensionWindowAdapter(browserManager: bm)
        }
        return windowAdapter != nil ? [windowAdapter!] : []
    }

    // MARK: - Permission prompting helper (invoked by delegate when needed)
    @available(macOS 15.4, *)
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
        let reqPerms = requestedPermissions.map { String(describing: $0) }
            .sorted()
        let optPerms = optionalPermissions.map { String(describing: $0) }
            .sorted()
        let reqHosts = requestedMatches.map { String(describing: $0) }.sorted()
        let optHosts = optionalMatches.map { String(describing: $0) }.sorted()

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
    @available(macOS 15.5, *)
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

    // Note: We can provide implementations for opening new tabs/windows once the
    // exact parameter types are finalized for the targeted SDK. These delegate
    // methods are optional; omitting them avoids type resolution issues across
    // SDK variations while retaining popup and permission handling.

    // MARK: - Opening tabs/windows requested by extensions
    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler:
            @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void
    ) {
        Self.logger.debug("   URL: \(configuration.url?.absoluteString ?? "nil")")
        Self.logger.debug("   Should be active: \(configuration.shouldBeActive)")
        Self.logger.debug("   Should be pinned: \(configuration.shouldBePinned)")

        guard let bm = browserManagerRef else {
            Self.logger.error("Browser manager reference is nil")
            completionHandler(
                nil,
                NSError(
                    domain: "ExtensionManager",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Browser manager not available"
                    ]
                )
            )
            return
        }

        // Special handling for extension page URLs (options, popup, etc.): use the extension's configuration
        if let url = configuration.url,
            url.scheme?.lowercased() == "safari-web-extension"
                || url.scheme?.lowercased() == "webkit-extension",
            let controller = extensionController,
            let resolvedContext = controller.extensionContext(for: url)
        {
            let space = bm.tabManager.currentSpace
            let newTab = bm.tabManager.createNewTab(
                url: url.absoluteString,
                in: space
            )
            let cfg =
                resolvedContext.webViewConfiguration
                ?? BrowserConfiguration.shared.webViewConfiguration
            newTab.applyWebViewConfigurationOverride(cfg)
            if configuration.shouldBePinned { bm.tabManager.pinTab(newTab) }
            if configuration.shouldBeActive {
                bm.tabManager.setActiveTab(newTab)
            }
            let tabAdapter = self.stableAdapter(for: newTab)
            completionHandler(tabAdapter, nil)
            return
        }

        let targetURL = configuration.url
        if let url = targetURL {
            let space = bm.tabManager.currentSpace
            let newTab = bm.tabManager.createNewTab(
                url: url.absoluteString,
                in: space
            )
            if configuration.shouldBePinned { bm.tabManager.pinTab(newTab) }
            if configuration.shouldBeActive {
                bm.tabManager.setActiveTab(newTab)
            }
            Self.logger.info("Created new tab: \(newTab.name)")

            // Return the created tab adapter to the extension
            let tabAdapter = self.stableAdapter(for: newTab)
            completionHandler(tabAdapter, nil)
            return
        }
        // No URL specified — create a blank tab
        Self.logger.debug("⚠️ No URL specified, creating blank tab")
        let space = bm.tabManager.currentSpace
        let newTab = bm.tabManager.createNewTab(in: space)
        if configuration.shouldBeActive { bm.tabManager.setActiveTab(newTab) }
        Self.logger.info("Created blank tab: \(newTab.name)")

        // Return the created tab adapter to the extension
        let tabAdapter = self.stableAdapter(for: newTab)
        completionHandler(tabAdapter, nil)
    }

    @available(macOS 15.5, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler:
            @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void
    ) {
        Self.logger.debug("   Tab URLs: \(configuration.tabURLs.map { $0.absoluteString })")

        guard let bm = browserManagerRef else {
            completionHandler(
                nil,
                NSError(
                    domain: "ExtensionManager",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Browser manager not available"
                    ]
                )
            )
            return
        }

        // OAuth flows from extensions should open in tabs to share the same data store
        // Miniwindows use separate data stores which breaks OAuth flows
        if let firstURL = configuration.tabURLs.first,
            OAuthDetector.isLikelyOAuthPopupURL(firstURL)
        {
            Self.logger.debug(
                "🔐 [DELEGATE] Extension OAuth window detected, opening in new tab: \(firstURL.absoluteString)"
            )
            // Create a new tab in the current space with the same profile/data store
            let newTab = bm.tabManager.createNewTab(
                url: firstURL.absoluteString,
                in: bm.tabManager.currentSpace
            )
            bm.tabManager.setActiveTab(newTab)

            // Return a dummy window adapter for OAuth flows
            if windowAdapter == nil {
                windowAdapter = ExtensionWindowAdapter(browserManager: bm)
            }
            completionHandler(windowAdapter, nil)
            return
        }

        // For regular extension windows, create a new space to emulate a separate window in our UI
        let newSpace = bm.tabManager.createSpace(name: "Window")
        if let firstURL = configuration.tabURLs.first {
            _ = bm.tabManager.createNewTab(
                url: firstURL.absoluteString,
                in: newSpace
            )
        } else {
            _ = bm.tabManager.createNewTab(in: newSpace)
        }
        bm.tabManager.setActiveSpace(newSpace)

        // Return the window adapter
        if windowAdapter == nil {
            windowAdapter = ExtensionWindowAdapter(browserManager: bm)
        }
        Self.logger.info("Created new window (space): \(newSpace.name)")
        completionHandler(windowAdapter, nil)
    }

    // MARK: - Native Messaging Support

    @available(macOS 15.5, *)
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
                let tab = browserManagerRef?.currentTabForActiveWindow()
                let adapter: ExtensionTabAdapter? = tab.flatMap { stableAdapter(for: $0) }
                extensionContext.performAction(for: adapter)
                replyHandler(["success": true], nil)
                return

            case "copyToClipboard":
                // Bitwarden Safari sends clipboard writes via native messaging.
                // Handle it by writing directly to NSPasteboard.
                let text = msg["text"] as? String ?? msg["data"] as? String ?? ""
                if !text.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                replyHandler(["success": true], nil)
                return

            case "readFromClipboard":
                // SECURITY: Clipboard read access is restricted to known extensions that
                // declare clipboard needs (e.g. password managers).
                let extensionId = extensionContext.uniqueIdentifier
                let extensionName = extensionContext.webExtension.displayName ?? "Unknown"

                // Allowlist of known extensions that legitimately need clipboard access
                let knownClipboardExtensions: Set<String> = [
                    "com.bitwarden.desktop.safari", // Bitwarden Safari
                    "com.8bit.bitwarden.safari",    // Bitwarden Safari (alt bundle)
                ]

                let hasClipboardPermission = knownClipboardExtensions.contains(extensionId)
                    || extensionContext.currentPermissions.contains(where: { String(describing: $0).lowercased().contains("clipboard") })

                if !hasClipboardPermission {
                    Self.logger.warning("[NativeMessaging] SECURITY: Denying clipboard read from extension '\(extensionName, privacy: .public)' (id: \(extensionId, privacy: .public)) — not in clipboard allowlist")
                    replyHandler(["text": "", "error": "Clipboard access denied"], nil)
                    return
                }

                Self.logger.info("[NativeMessaging] Allowing clipboard read for extension '\(extensionName, privacy: .public)' (id: \(extensionId, privacy: .public))")
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
        if unavailableNativeHosts.contains(applicationId) {
            replyHandler(["command": "disconnected"] as [String: Any], nil)
            return
        }

        Self.logger.info("[NativeMessaging] sendMessage to '\(applicationId, privacy: .public)'")

        // Single-shot message handling
        let handler = NativeMessagingHandler(applicationId: applicationId)
        handler.sendMessage(message) { [weak self] response, error in
            // If the host failed to launch, cache it as unavailable
            if error != nil && response == nil {
                self?.unavailableNativeHosts.insert(applicationId)
                Self.logger.info("[NativeMessaging] Marked '\(applicationId, privacy: .public)' as unavailable (host not found)")
            }
            replyHandler(response, error)
        }
    }

    @available(macOS 15.5, *)
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
        if unavailableNativeHosts.contains(applicationId) {
            Self.logger.debug("[NativeMessaging] Handling port internally for '\(applicationId, privacy: .public)' (no external host)")
            setupInternalPortHandler(port: port, extensionContext: extensionContext, applicationId: applicationId)
            completionHandler(nil)
            return
        }

        let handler = NativeMessagingHandler(applicationId: applicationId)
        nativeMessagingHandlers.append(handler)
        handler.connect(port: port) { [weak self] hostFound in
            guard let self else { return }
            if !hostFound {
                self.unavailableNativeHosts.insert(applicationId)
                Self.logger.info("[NativeMessaging] Marked '\(applicationId, privacy: .public)' as unavailable (host not found via port)")
                // External host not available — fall back to internal handling
                // so the port stays alive and Safari extension commands still work
                self.setupInternalPortHandler(port: port, extensionContext: extensionContext, applicationId: applicationId)
            }
            // Clean up handler reference
            self.nativeMessagingHandlers.removeAll { $0 === handler }
        }
        completionHandler(nil)
    }

    // MARK: - Internal Port Handler for Safari Extensions

    /// Handle a native messaging port internally when no external host is available.
    /// Safari extensions (.appex) expect their host app to respond on this channel.
    ///
    /// Routes messages through registered `InternalNativePortHandler` instances first
    /// (e.g. Bitwarden biometric handler), then falls back to generic command handling
    /// (clipboard, popover) that's common across many Safari extensions.
    @available(macOS 15.5, *)
    private func setupInternalPortHandler(
        port: WKWebExtension.MessagePort,
        extensionContext: WKWebExtensionContext,
        applicationId: String? = nil
    ) {
        // Resolve a registered handler for this application identifier
        let registeredHandler: (any InternalNativePortHandler)? =
            applicationId.flatMap { internalHandler(for: $0) }

        port.messageHandler = { [weak self] (_, message) in
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
                    let text = msg["text"] as? String ?? msg["data"] as? String ?? ""
                    if !text.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    port.sendMessage(["command": command, "success": true] as [String: Any]) { _ in }

                case "readFromClipboard":
                    let text = NSPasteboard.general.string(forType: .string) ?? ""
                    port.sendMessage(["command": command, "text": text] as [String: Any]) { _ in }

                case "showPopover":
                    let tab = self?.browserManagerRef?.currentTabForActiveWindow()
                    let adapter: ExtensionTabAdapter? = tab.flatMap { self?.stableAdapter(for: $0) }
                    extensionContext.performAction(for: adapter)
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
    @available(macOS 15.5, *)
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

        // Provide a lightweight alias to help extensions that only check `chrome`.
        // This only affects the options page web view, not normal websites.
        let aliasJS = """
            if (typeof window.chrome === 'undefined' && typeof window.browser !== 'undefined') {
              try { window.chrome = window.browser; } catch (e) {}
            }
            """
        let aliasScript = WKUserScript(
            source: aliasJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        webView.configuration.userContentController.addUserScript(aliasScript)

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
    @available(macOS 15.5, *)
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
    @available(macOS 15.5, *)
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
    @available(macOS 15.5, *)
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

    // MARK: - URL Conversion Helpers

    /// Convert extension URL (webkit-extension:// or safari-web-extension://) to file URL
    @available(macOS 15.5, *)
    private func convertExtensionURLToFileURL(
        _ urlString: String,
        for context: WKWebExtensionContext
    ) -> URL? {
        Self.logger.debug("🔄 [convertExtensionURLToFileURL] Converting: \(urlString)")

        // Extract the path from the extension URL
        guard let url = URL(string: urlString) else {
            Self.logger.error("Invalid URL string")
            return nil
        }

        let path = url.path

        // Find the corresponding installed extension
        if let extId = extensionContexts.first(where: { $0.value === context })?
            .key,
            let inst = installedExtensions.first(where: { $0.id == extId })
        {
            Self.logger.debug("   📦 Found extension: \(inst.name)")

            // Build file URL from extension package path
            let extensionURL = URL(fileURLWithPath: inst.packagePath)
            let fileURL = extensionURL.appendingPathComponent(
                path.hasPrefix("/") ? String(path.dropFirst()) : path
            )

            // Verify the file exists
            if FileManager.default.fileExists(atPath: fileURL.path) {
                Self.logger.info("File exists at: \(fileURL.path)")
                return fileURL
            } else {
                Self.logger.error("File not found at: \(fileURL.path)")
            }
        } else {
            Self.logger.error("Could not find installed extension for context")
        }

        return nil
    }
}
