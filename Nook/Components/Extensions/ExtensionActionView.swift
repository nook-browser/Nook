//
//  ExtensionActionView.swift
//  Nook
//
//  Clean ExtensionActionView using ONLY native WKWebExtension APIs
//

import AppKit
import SwiftUI
import WebKit

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
    @EnvironmentObject var windowState: BrowserWindowState

    var body: some View {
        Button(action: {
            showExtensionPopup()
        }) {
            Group {
                if let iconPath = ext.iconPath,
                   let nsImage = NSImage(contentsOfFile: iconPath)
                {
                    Image(nsImage: nsImage)
                        .resizable()
                } else {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundColor(.blue)
                }
            }
            .frame(width: 20, height: 20)
            .background(ActionAnchorView(extensionId: ext.id))
        }
        .buttonStyle(.plain)
        .help(ext.name)
    }

    private func showExtensionPopup() {
        print("🎯 Performing action for extension: \(ext.name)")

        guard let extensionContext = ExtensionManager.shared.getExtensionContext(for: ext.id) else {
            print("❌ No extension context found")
            return
        }

        print("✅ Calling performAction() - this should trigger the delegate")
        if let current = browserManager.currentTab(for: windowState) {
            if let adapter = ExtensionManager.shared.stableAdapter(for: current) {
                extensionContext.performAction(for: adapter)
            } else {
                extensionContext.performAction(for: nil)
            }
        } else {
            extensionContext.performAction(for: nil)
        }
    }
}

@available(macOS 15.5, *)
#Preview {
    ExtensionActionView(extensions: [])
}

// MARK: - Anchor View for Popover Positioning

private struct ActionAnchorView: NSViewRepresentable {
    let extensionId: String

    func makeNSView(context _: Context) -> NSView {
        let view = NSView(frame: .zero)
        if #available(macOS 15.5, *) {
            ExtensionManager.shared.setActionAnchor(for: extensionId, anchorView: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        if #available(macOS 15.5, *) {
            ExtensionManager.shared.setActionAnchor(for: extensionId, anchorView: nsView)
        }
    }
}
