// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  ExternalMiniWindowManager.swift
//  Nook
//
//  Created by Jonathan Caudill on 26/08/2025.
//

import SwiftUI
import WebKit
import AppKit
import Combine
import NookWeb

@MainActor
final class MiniWindowSession: ObservableObject, Identifiable {
    let id = UUID()
    let profile: Profile?
    let originName: String
    private let targetSpaceResolver: () -> String
    private let adoptHandler: (MiniWindowSession) -> Void
    private let authCompletionHandler: ((Bool, URL?) -> Void)?

    @Published var currentURL: URL
    @Published var title: String
    @Published var isAuthComplete: Bool = false
    @Published var authSuccess: Bool = false

    /// The loaded page, handed to the new tab on adopt so it does not reload.
    weak var webView: WKWebView?

    init(
        url: URL,
        profile: Profile?,
        originName: String,
        targetSpaceResolver: @escaping () -> String,
        adoptHandler: @escaping (MiniWindowSession) -> Void,
        authCompletionHandler: ((Bool, URL?) -> Void)? = nil
    ) {
        self.profile = profile
        self.originName = originName
        self.targetSpaceResolver = targetSpaceResolver
        self.adoptHandler = adoptHandler
        self.authCompletionHandler = authCompletionHandler
        self.currentURL = url
        self.title = url.absoluteString
    }

    var targetSpaceName: String { targetSpaceResolver() }

    func adopt() {
        adoptHandler(self)
    }

    func updateNavigationState(url: URL?, title: String?) {
        if let url { currentURL = url }
        if let title, !title.isEmpty { self.title = title }
    }

    func completeAuth(success: Bool, finalURL: URL? = nil) {
        isAuthComplete = true
        authSuccess = success
        if let finalURL = finalURL {
            currentURL = finalURL
        }
        authCompletionHandler?(success, finalURL)
        
        // Don't auto-adopt - let the user decide when to adopt the window
        // The authentication completion is communicated back to the original tab
        // but the mini window stays open for the user to manually adopt if desired
    }

    func cancelAuthDueToClose() {
        guard !isAuthComplete else { return }
        authCompletionHandler?(false, nil)
    }
}

@MainActor
final class ExternalMiniWindowManager {
    private struct SessionEntry {
        let controller: MiniBrowserWindowController
    }

    private weak var browserManager: BrowserManager?
    private var sessions: [UUID: SessionEntry] = [:]

    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func present(url: URL, authCompletionHandler: ((Bool, URL?) -> Void)? = nil) {
        guard let browserManager else { return }
        let window = browserManager.windowRegistry?.activeWindow
        let profile = window.flatMap { window in
            window.isIncognito
                ? window.ephemeralProfile
                : window.spaceID.flatMap { browserManager.tabs.profile(forSpace: $0) }
        } ?? browserManager.currentProfile
        let session = MiniWindowSession(
            url: url,
            profile: profile,
            originName: profile?.name ?? "Default",
            targetSpaceResolver: { [weak browserManager] in
                guard let browserManager else { return "Current Space" }
                let tabs = browserManager.tabs
                let space = browserManager.windowRegistry?.activeWindow?.spaceID.flatMap { tabs.space($0) }
                    ?? tabs.orderedSpaces.first
                return space?.name ?? "Current Space"
            },
            adoptHandler: { [weak self] session in
                self?.adopt(session: session)
            },
            authCompletionHandler: authCompletionHandler
        )

        let controller = MiniBrowserWindowController(
            session: session,
            adoptAction: { [weak session] in session?.adopt() },
            onClose: { [weak self] session in
                session.cancelAuthDueToClose()
                self?.sessions[session.id] = nil
            },
            gradientColorManager: browserManager.gradientColorManager
        )

        sessions[session.id] = SessionEntry(controller: controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func adopt(session: MiniWindowSession) {
        guard let browserManager, let window = browserManager.windowRegistry?.activeWindow else { return }
        let tabs = browserManager.tabs

        // The live page carries its space's data store; only reuse it when the window shows
        // that same space, otherwise reload in the space's own store.
        let windowStoreID = window.isIncognito ? window.ephemeralProfile?.id : window.spaceID
        if let webView = session.webView, windowStoreID == session.profile?.id {
            tabs.adopt(webView: webView, url: session.currentURL, title: webView.title ?? session.currentURL.host ?? "",
                       in: window, placement: .newTab)
        } else {
            tabs.open(url: session.currentURL, in: window, placement: .newTab)
        }

        sessions[session.id]?.controller.close()
        sessions[session.id] = nil
    }
}

// MARK: - Mini Browser Window Controller

private extension NSToolbarItem.Identifier {
    static let miniOpenInSpace = NSToolbarItem.Identifier("com.nook.miniwindow.openInSpace")
    static let miniShare = NSToolbarItem.Identifier("com.nook.miniwindow.share")
}

/// Carries ⌘O for "open in space": a toolbar item cannot hold a key equivalent,
/// and the window is not part of the app's menu-bar command tree.
final class MiniBrowserWindow: NSWindow {
    var openInSpaceAction: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "o" {
            openInSpaceAction?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class MiniBrowserWindowController: NSWindowController, NSWindowDelegate {
    private let session: MiniWindowSession
    private let adoptAction: () -> Void
    private let onClose: (MiniWindowSession) -> Void
    private let gradientColorManager: GradientColorManager
    private var titleObservers: Set<AnyCancellable> = []

    private static let maximumSize = NSSize(width: 1280, height: 900)
    private static let minimumSize = NSSize(width: 640, height: 480)

    /// Three quarters of the screen, capped so it still reads as a small window on large displays.
    private static var defaultSize: NSSize {
        let visible = NSScreen.main?.visibleFrame.size ?? maximumSize
        return NSSize(
            width: max(minimumSize.width, min(maximumSize.width, visible.width * 0.75)),
            height: max(minimumSize.height, min(maximumSize.height, visible.height * 0.85))
        )
    }

    init(session: MiniWindowSession, adoptAction: @escaping () -> Void, onClose: @escaping (MiniWindowSession) -> Void, gradientColorManager: GradientColorManager) {
        self.session = session
        self.adoptAction = adoptAction
        self.onClose = onClose
        self.gradientColorManager = gradientColorManager

        let contentView = MiniBrowserWindowView(session: session)
            .environmentObject(gradientColorManager)

        let hostingController = NSHostingController(rootView: contentView)
        let window = MiniBrowserWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimumSize
        // Without this the hosting controller shrinks the window to the view's minimum size.
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.setContentSize(Self.defaultSize)
        window.center()

        super.init(window: window)

        window.delegate = self
        window.openInSpaceAction = adoptAction
        window.subtitle = session.originName
        installToolbar(on: window)
        observeNavigationState(for: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(sender)
    }

    func windowWillClose(_ notification: Notification) {
        onClose(session)
    }

    @objc private func openInSpace(_ sender: Any?) {
        adoptAction()
    }

    // MARK: - Toolbar

    private func installToolbar(on window: NSWindow) {
        let toolbar = NSToolbar(identifier: "com.nook.miniwindow.toolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbarStyle = .unified
        window.toolbar = toolbar
    }

    /// Mirrors the page into the window's title and the space into its subtitle,
    /// so the toolbar carries no label views of its own.
    private func observeNavigationState(for window: NSWindow) {
        session.$currentURL
            .sink { [weak window] url in
                window?.title = url.host() ?? url.absoluteString
            }
            .store(in: &titleObservers)
    }
}

extension MiniBrowserWindowController: NSToolbarDelegate {
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, .miniOpenInSpace, .miniShare]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .miniShare:
            let item = NSSharingServicePickerToolbarItem(itemIdentifier: itemIdentifier)
            item.delegate = self
            item.toolTip = "Share"
            return item
        case .miniOpenInSpace:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.title = "Open in \(session.targetSpaceName)"
            item.toolTip = "Open this page as a tab in \(session.targetSpaceName) (⌘O)"
            item.isBordered = true
            item.target = self
            item.action = #selector(openInSpace(_:))
            return item
        default:
            return nil
        }
    }
}

extension MiniBrowserWindowController: NSSharingServicePickerToolbarItemDelegate {
    /// The SDK declares this requirement `NS_SWIFT_UI_ACTOR`, so it is already main-actor
    /// isolated. Marking it `nonisolated` forced a `MainActor.assumeIsolated` whose executor
    /// check segfaults in the concurrency runtime on macOS 27 (26A428) during toolbar validation.
    func items(for pickerToolbarItem: NSSharingServicePickerToolbarItem) -> [Any] {
        [session.currentURL]
    }
}
