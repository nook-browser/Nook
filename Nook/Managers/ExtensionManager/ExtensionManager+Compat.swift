// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionManager+Compat.swift
//  Nook
//
//  Wires `ExtensionCompatBridge` to the app: which APIs it answers, and the app services they use.
//

import AppKit
import Foundation
import NookWeb
import SwiftData
import UserNotifications
import WebKit

extension ExtensionManager {
    /// The stored form of a granted `nativeMessaging`, as `persistGrantedOptionalPermissions` writes it.
    private static var nativeMessagingGrant: String { String(describing: WKWebExtension.Permission.nativeMessaging) }

    func setupCompatBridge() {
        let offscreen = ExtensionCompatOffscreen()
        offscreen.shimSource = { [weak self] context in
            guard let path = self?.fetchEntity(id: context.uniqueIdentifier)?.packagePath else { return nil }
            return try? String(contentsOf: URL(fileURLWithPath: path).appendingPathComponent(ExtensionCompatPatcher.shimFile), encoding: .utf8)
        }
        compatBridge.register(offscreen)
        compatBridge.register(compatWebNavigation)

        let idle = ExtensionCompatIdle(bridge: compatBridge)
        // Pointer events reach a global monitor without Accessibility access; keys only inside Nook.
        idle.onNextInput = { seen in
            let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]
            let monitors = [NSEvent.addGlobalMonitorForEvents(matching: mask) { _ in seen() },
                            NSEvent.addLocalMonitorForEvents(matching: mask) { seen(); return $0 }]
            return { monitors.compactMap { $0 }.forEach(NSEvent.removeMonitor) }
        }
        compatBridge.register(idle)

        let notifications = ExtensionCompatNotifications(bridge: compatBridge)
        notificationCenter.api = notifications
        notifications.center = notificationCenter
        notifications.context = { [weak self] in self?.extensionContexts[$0] }
        UNUserNotificationCenter.current().delegate = notificationCenter
        compatBridge.register(notifications)

        let identity = ExtensionCompatIdentity()
        identity.present = { [weak self] url, redirected, closed in self?.presentAuthFlow(url, redirected: redirected, closed: closed) }
        identity.hiddenView = { [weak self] in
            // Never a private window's cookies: the extension may not be allowed in one.
            guard let profile = self?.authFlowSpace()?.profile, !profile.isEphemeral else { return nil }
            // A configuration of its own, so no extension's scripts run in the page.
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = profile.dataStore
            // Nobody can click in it, so nothing in it plays.
            configuration.mediaTypesRequiringUserActionForPlayback = .all
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 768), configuration: configuration)
            view.customUserAgent = PlatformUserAgent.custom
            return view
        }
        compatBridge.register(identity)

        // Nook has no side panel: the page gets the window `windows.create({type: "popup"})` gets, at a panel's proportions.
        compatSidePanel.present = { [weak self] url, context, closed in
            guard let self, let controller = self.extensionController,
                  let popup = self.openExtensionPopupWindow(
                      url, frame: CGRect(x: CGFloat.nan, y: CGFloat.nan, width: 400, height: 720), focused: true,
                      extensionContext: context, controller: controller, closed: closed)
            else { return nil }
            return ExtensionCompatSidePanel.Panel(focus: { [weak popup] in popup?.show() }, close: { [weak popup] in popup?.window.close() })
        }
        compatBridge.register(compatSidePanel)

        compatManagement.installed = { [weak self] in
            guard let self else { return [] }
            return self.installedExtensions.map(self.managementInfo)
        }
        compatManagement.contexts = { [weak self] in Array((self?.extensionContexts ?? [:]).values) }
        compatBridge.register(compatManagement)

        // An extension whose manifest lists nativeMessaging as optional asks for it at run time.
        // WebKit would not prompt, since Nook's channel already holds the permission.
        compatBridge.askForNativeMessaging = { [weak self] context, done in
            guard let self else { return done(false) }
            self.presentPermissionPrompt(
                requestedPermissions: [.nativeMessaging], optionalPermissions: [],
                requestedMatches: [], optionalMatches: [],
                extensionDisplayName: context.webExtension.displayName ?? "Extension",
                isRuntimeRequest: true,
                onDecision: { _, _ in done(true) },
                onCancel: { done(false) },
                extensionLogo: context.webExtension.icon(for: .init(width: 64, height: 64)) ?? NSImage())
        }
        compatBridge.nativeMessagingGrantChanged = { [weak self] context, granted in
            guard let self, let entity = self.fetchEntity(id: context.uniqueIdentifier) else { return }
            var grants = Set(entity.grantedOptionalPermissions ?? [])
            if granted { grants.insert(Self.nativeMessagingGrant) } else { grants.remove(Self.nativeMessagingGrant) }
            entity.grantedOptionalPermissions = Array(grants)
            try? self.context.save()
        }
    }

    /// `webNavigation.onHistoryStateUpdated` and `onReferenceFragmentUpdated`, which WebKit never fires.
    func notifySameDocumentNavigation(_ session: PageSession, from old: URL) {
        guard let adapter = openedAdapter(for: session.itemID) else { return }
        compatWebNavigation.sameDocumentNavigation(
            from: old, to: session.url, in: adapter, isPrivate: session.isPrivate, contexts: extensionContexts.values)
    }

    /// The space in front, whose cookies a sign-in flow uses.
    private func authFlowSpace() -> (profile: Profile, window: BrowserWindowState?)? {
        guard let browserManager = browserManagerRef else { return nil }
        let window = browserManager.windowRegistry?.mostRecentRegularWindow
        let profile = window?.spaceID.flatMap { browserManager.tabs.profile(forSpace: $0) } ?? browserManager.currentProfile
        return profile.map { ($0, window) }
    }

    /// A sign-in page for `identity.launchWebAuthFlow`, in a mini window with the cookies of the space in front.
    private func presentAuthFlow(_ url: URL, redirected: @escaping (URL) -> Bool, closed: @escaping () -> Void) -> (() -> Void)? {
        guard let browserManager = browserManagerRef, let (profile, window) = authFlowSpace() else { return nil }
        let page = browserManager.tabs.openDetached(url: url, profile: profile, in: window)
        page.navigationInterceptor = redirected
        // Closed by the person, or moved to a tab: either way the flow is over.
        let shown = browserManager.externalMiniWindowManager.present(page) { [weak page] in
            page?.navigationInterceptor = nil
            closed()
        }
        guard shown else {
            browserManager.tabs.endDetached(page)
            return nil
        }
        return { [weak page] in page?.onClose?() }
    }

    /// An installed extension as `chrome.management` describes it, with what only a loaded one has.
    func managementInfo(_ installed: InstalledExtension) -> ExtensionCompatManagement.Info {
        var info = installed.managementInfo
        info.baseURL = extensionContexts[installed.id]?.baseURL
        return info
    }

    /// `management.onInstalled`, `onEnabled` and `onDisabled` for the other extensions.
    func notifyManagement(_ extensionId: String, _ change: (ExtensionCompatManagement.Info) -> ExtensionCompatManagement.Change) {
        guard let installed = installedExtensions.first(where: { $0.id == extensionId }) else { return }
        compatManagement.changed(change(managementInfo(installed)))
    }

    /// Tells the bridge what this package may do with native messaging before it can send any.
    func loadCompatState(for context: WKWebExtensionContext, entity: ExtensionEntity) {
        let added = ExtensionCompatPatcher.addedPermissions(packageAt: URL(fileURLWithPath: entity.packagePath))
        compatBridge.contextLoaded(
            context, ownsChannel: added.contains(ExtensionCompatPatcher.channelPermission),
            nativeMessagingGranted: entity.grantedOptionalPermissions?.contains(Self.nativeMessagingGrant) == true)
    }
}

extension InstalledExtension {
    var managementInfo: ExtensionCompatManagement.Info {
        ExtensionCompatManagement.Info(
            id: id, name: name, version: version, description: description ?? "", enabled: isEnabled, manifest: manifest,
            added: ExtensionCompatPatcher.addedPermissions(packageAt: URL(fileURLWithPath: packagePath)))
    }
}
