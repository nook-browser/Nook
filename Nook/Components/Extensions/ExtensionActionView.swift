// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionActionView.swift
//  Nook
//
//  Clean ExtensionActionView using ONLY native WKWebExtension APIs
//

import SwiftUI
import WebKit
import AppKit
import os
import NookDesign
import NookSettings
import NookWeb
import NookUI

struct ExtensionActionView: View {
    let extensions: [InstalledExtension]
    @EnvironmentObject var browserManager: BrowserManager
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(extensions.filter { $0.isEnabled }, id: \.id) { ext in
                ExtensionActionButton(ext: ext)
                    .environmentObject(browserManager)
            }
        }
    }
}

struct ExtensionActionButton: View {
    let ext: InstalledExtension
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @State private var isHovering: Bool = false
    @State private var badgeText: String?
    @State private var badgeRefreshId: UUID = UUID()

    private var currentSession: PageSession? {
        browserManager.tabs.selectedSession(in: windowState)
    }

    var body: some View {
        Button(action: {
            showExtensionPopup()
        }) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let iconPath = ext.iconPath,
                       let nsImage = NSImage(contentsOfFile: iconPath) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .interpolation(.high)
                            .antialiased(true)
                            .scaledToFit()
                    } else {
                        Image(systemName: "puzzlepiece.extension")
                            .foregroundStyle(.primary)
                    }
                }
                .frame(width: 16, height: 16)

                if let badge = badgeText, !badge.isEmpty {
                    Text(badge)
                        .font(NookDesign.Font.micro)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -4)
                }
            }
            .frame(width: NookDesign.Size.iconButton, height: NookDesign.Size.iconButton)
            .background(isHovering ? NookDesign.Surface.fillPressed : .clear)
            .background(ActionAnchorView(extensionId: ext.id))
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
        }
        .buttonStyle(.plain)
        .help(ext.name)
        .onHoverTracking { state in
            isHovering = state
        }
        .onAppear { refreshBadge() }
        .onReceive(NotificationCenter.default.publisher(for: .adBlockerStateChanged)) { _ in
            refreshBadge()
        }
        // Wake workers when returning to Nook from another app. MV3 workers
        // auto-terminate after ~5 min of inactivity; if the user was away, the
        // worker may be dead and badge state cleared. Tab switches already wake
        // workers via notifyTabActivated — this covers the app-reactivation case.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            wakeAndRefreshBadge()
        }
        .onChange(of: currentSession?.url) { _, _ in
            refreshBadge()
        }
        .onChange(of: currentSession?.loadingState) { _, newState in
            if newState == .didFinish {
                // Small delay to let extension background process the tab update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    refreshBadge()
                }
            }
        }
    }

    /// Wake background workers then refresh the badge after a short delay.
    /// Called on app reactivation; MV3 workers may have terminated while Nook was in the background.
    private func wakeAndRefreshBadge() {
        ExtensionManager.shared.wakeBackgroundWorkers()
        // Give the worker time to process the current tab and update badge text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            refreshBadge()
        }
    }

    private func refreshBadge() {
        guard let ctx = ExtensionManager.shared.getExtensionContext(for: ext.id) else {
            badgeText = nil
            return
        }
        let adapter = ExtensionManager.shared.actionAdapter(in: windowState)
        let action = ctx.action(for: adapter)
        badgeText = action?.badgeText
    }
    
    private static let logger = Logger(subsystem: "com.nook.browser", category: "ExtensionAction")

    private func showExtensionPopup() {
        Self.logger.notice("Action tapped for '\(self.ext.name, privacy: .public)' id=\(self.ext.id, privacy: .public)")

        guard let extensionContext = ExtensionManager.shared.getExtensionContext(for: ext.id) else {
            Self.logger.error("No extension context for id=\(self.ext.id, privacy: .public). Available: \(ExtensionManager.shared.loadedContextIDs.joined(separator: ", "), privacy: .public)")
            return
        }

        let session = currentSession
        let adapter = ExtensionManager.shared.actionAdapter(in: windowState)

        // No permission grants here: required permissions were granted at load, site access
        // follows the extension's approved patterns, and activeTab is granted by WebKit on click.

        let perform = {
            Self.logger.notice("Calling performAction (tab=\(session?.title ?? "nil", privacy: .public), adapter=\(adapter != nil ? "yes" : "nil", privacy: .public))")
            extensionContext.performAction(for: adapter)
        }
        guard extensionContext.webExtension.hasBackgroundContent else { return perform() }

        // Wait for the background page so the popup does not spin, but never more than 1.5 s:
        // a background load that fails can leave WebKit's wake callback uncalled, and the click
        // then did nothing at all.
        var performed = false
        let performOnce = { (reason: String) in
            guard !performed else { return }
            performed = true
            if reason != "ready" { Self.logger.notice("Opening popup without background page: \(reason, privacy: .public)") }
            perform()
        }
        extensionContext.loadBackgroundContent { error in
            DispatchQueue.main.async { performOnce(error.map { "wake failed: \($0.localizedDescription)" } ?? "ready") }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { performOnce("wake timed out") }
    }
}

#Preview {
    ExtensionActionView(extensions: [])
}

// MARK: - Anchor View for Popover Positioning
private struct ActionAnchorView: NSViewRepresentable {
    let extensionId: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        ExtensionManager.shared.setActionAnchor(for: extensionId, anchorView: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        ExtensionManager.shared.setActionAnchor(for: extensionId, anchorView: nsView)
    }
}
