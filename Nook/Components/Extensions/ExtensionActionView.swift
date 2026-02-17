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
    
    var body: some View {
        Button(action: {
            showExtensionPopup()
        }) {
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
            .padding(6)
            .background(isHovering ? .white.opacity(0.1) : .clear)
            .background(ActionAnchorView(extensionId: ext.id))
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .help(ext.name)
        .onHover { state in
            isHovering = state
            
        }
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
