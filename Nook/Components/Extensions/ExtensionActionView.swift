//
//  ExtensionActionView.swift
//  Nook
//
//  Clean ExtensionActionView using ONLY native WKWebExtension APIs
//

import NookSettings
import SwiftUI
import NookDesign
import WebKit
import AppKit
import os

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
                            .foregroundColor(.white)
                    }
                }
                .frame(width: 16, height: 16)

                if let badge = badgeText, !badge.isEmpty {
                    Text(badge)
                        .font(NookDesign.Font.micro)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -4)
                }
            }
            .padding(6)
            .background(isHovering ? .white.opacity(0.1) : .clear)
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
        let adapter = currentSession.flatMap { ExtensionManager.shared.adapter(for: $0.itemID) }
        let action = ctx.action(for: adapter)
        badgeText = action?.badgeText
    }
    
    private static let logger = Logger(subsystem: "com.nook.browser", category: "ExtensionAction")

    private func showExtensionPopup() {
        Self.logger.info("Action tapped for '\(self.ext.name, privacy: .public)' id=\(self.ext.id, privacy: .public)")

        guard let extensionContext = ExtensionManager.shared.getExtensionContext(for: ext.id) else {
            Self.logger.error("No extension context for id=\(self.ext.id, privacy: .public). Available: \(ExtensionManager.shared.loadedContextIDs.joined(separator: ", "), privacy: .public)")
            return
        }

        let session = currentSession
        let adapter = session.flatMap { ExtensionManager.shared.adapter(for: $0.itemID) }

        // No permission grants here: required permissions were granted at load, site access
        // follows the extension's approved patterns, and activeTab is granted by WebKit on click.

        // Wake background worker and AWAIT it before triggering the action.
        // MV3 workers auto-terminate after ~5 min; if the popup opens before the
        // worker is alive, chrome.runtime.sendMessage hangs and the popup shows
        // a spinner for several seconds.
        if extensionContext.webExtension.hasBackgroundContent {
            Task { @MainActor in
                do {
                    try await extensionContext.loadBackgroundContent()
                    Self.logger.debug("Background worker alive for '\(self.ext.name, privacy: .public)'")
                } catch {
                    Self.logger.error("Background wake failed: \(error.localizedDescription, privacy: .public)")
                }
                Self.logger.info("Calling performAction (tab=\(session?.title ?? "nil", privacy: .public), adapter=\(adapter != nil ? "yes" : "nil", privacy: .public))")
                extensionContext.performAction(for: adapter)
            }
        } else {
            Self.logger.info("Calling performAction (tab=\(session?.title ?? "nil", privacy: .public), adapter=\(adapter != nil ? "yes" : "nil", privacy: .public))")
            extensionContext.performAction(for: adapter)
        }
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
