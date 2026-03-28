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

@available(macOS 15.5, *)
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

@available(macOS 15.5, *)
struct ExtensionActionButton: View {
    let ext: InstalledExtension
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @State private var isHovering: Bool = false
    @State private var badgeText: String?
    @State private var badgeRefreshId: UUID = UUID()

    private var currentTab: Tab? {
        browserManager.currentTab(for: windowState)
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
                        .font(.system(size: 8, weight: .bold))
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
            .clipShape(RoundedRectangle(cornerRadius: 7))
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
        .onChange(of: currentTab?.url) { _, _ in
            refreshBadge()
        }
        .onChange(of: currentTab?.loadingState) { _, newState in
            if newState == .didFinish {
                // Small delay to let extension background process the tab update
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    refreshBadge()
                }
            }
        }
    }

    private func refreshBadge() {
        guard let ctx = ExtensionManager.shared.getExtensionContext(for: ext.id) else {
            badgeText = nil
            return
        }
        let tab = currentTab
        let adapter: ExtensionTabAdapter? = tab.flatMap { ExtensionManager.shared.stableAdapter(for: $0) }
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

        // Wake background worker before triggering the action so the popup
        // doesn't hang waiting for a dead service worker to respond.
        if extensionContext.webExtension.hasBackgroundContent {
            extensionContext.loadBackgroundContent { error in
                if let error {
                    Self.logger.error("Background wake failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        let tab = browserManager.currentTab(for: windowState)
        let adapter: ExtensionTabAdapter? = tab.flatMap { ExtensionManager.shared.stableAdapter(for: $0) }
        Self.logger.info("Calling performAction (tab=\(tab?.name ?? "nil", privacy: .public), adapter=\(adapter != nil ? "yes" : "nil", privacy: .public))")
        extensionContext.performAction(for: adapter)
    }
}

@available(macOS 15.5, *)
#Preview {
    ExtensionActionView(extensions: [])
}

// MARK: - Anchor View for Popover Positioning
private struct ActionAnchorView: NSViewRepresentable {
    let extensionId: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        if #available(macOS 15.5, *) {
            ExtensionManager.shared.setActionAnchor(for: extensionId, anchorView: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 15.5, *) {
            ExtensionManager.shared.setActionAnchor(for: extensionId, anchorView: nsView)
        }
    }
}
