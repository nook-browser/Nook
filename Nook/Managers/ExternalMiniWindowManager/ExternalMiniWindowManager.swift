//
//  ExternalMiniWindowManager.swift
//  Nook
//
//  Created by Jonathan Caudill on 26/08/2025.
//

import SwiftUI
import WebKit
import AppKit
import Observation

@MainActor
@Observable
final class MiniWindowSession: Identifiable {
    let id = UUID()
    let profile: Profile?
    let originName: String
    private let targetSpaceResolver: () -> String
    private let adoptHandler: (MiniWindowSession) -> Void
    private let authCompletionHandler: ((Bool, URL?) -> Void)?

    var currentURL: URL
    var title: String
    var isLoading: Bool = true
    var estimatedProgress: Double = 0
    var isAuthComplete: Bool = false
    var authSuccess: Bool = false
    var toolbarColor: NSColor?

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

    func updateLoading(isLoading: Bool) {
        self.isLoading = isLoading
    }

    func updateProgress(_ progress: Double) {
        estimatedProgress = progress
    }
    
    func updateToolbarColor(hexString: String?) {
        guard let trimmed = hexString?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            toolbarColor = nil
            return
        }

        if let color = NSColor(hex: trimmed) {
            toolbarColor = color.usingColorSpace(.sRGB)
        } else {
            toolbarColor = nil
        }
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
        let profile = browserManager.currentProfile
        let session = MiniWindowSession(
            url: url,
            profile: profile,
            originName: profile?.name ?? "Default",
            targetSpaceResolver: { [weak browserManager] in
                // Try to get the current space, or fall back to the first available space
                if let currentSpace = browserManager?.tabManager.currentSpace {
                    return currentSpace.name
                } else if let firstSpace = browserManager?.tabManager.spaces.first {
                    return firstSpace.name
                } else {
                    return "Current Space"
                }
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
            gradientColorManager: GradientColorManager.shared
        )

        sessions[session.id] = SessionEntry(controller: controller)
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func adopt(session: MiniWindowSession) {
        guard let browserManager else { return }

        // Find the target space - try current space first, then fall back to space name matching
        let targetSpace = browserManager.tabManager.currentSpace ??
                         browserManager.tabManager.spaces.first { $0.name == session.targetSpaceName } ??
                         browserManager.tabManager.spaces.first

        let newTab = browserManager.tabManager.createNewTab(url: session.currentURL.absoluteString, in: targetSpace)
        browserManager.tabManager.setActiveTab(newTab)

        // If this is the first window opening, set this as the active space for the browser manager
        if browserManager.tabManager.currentSpace == nil, let space = targetSpace {
            browserManager.tabManager.setActiveSpace(space)
        }

        sessions[session.id]?.controller.close()
        sessions[session.id] = nil
    }
}

// MARK: - Mini Browser Window Controller

@MainActor
final class MiniBrowserWindowController: NSWindowController, NSWindowDelegate {
    private let session: MiniWindowSession
    private let adoptAction: () -> Void
    private let onClose: (MiniWindowSession) -> Void
    private let gradientColorManager: GradientColorManager

    init(session: MiniWindowSession, adoptAction: @escaping () -> Void, onClose: @escaping (MiniWindowSession) -> Void, gradientColorManager: GradientColorManager) {
        self.session = session
        self.adoptAction = adoptAction
        self.onClose = onClose
        self.gradientColorManager = gradientColorManager

        let contentView = MiniBrowserWindowView(
            session: session,
            adoptAction: adoptAction,
            dismissAction: { [weak session] in
                guard let session else { return }
                onClose(session)
            }
        )
        .nookTheme(gradientColorManager)

        let hostingController = NSHostingController(rootView: contentView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = hostingController

        super.init(window: window)

        window.delegate = self
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
}
