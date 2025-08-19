//
//  ExtensionActionView.swift
//  Pulse
//
//  Clean ExtensionActionView using ONLY native WKWebExtension APIs
//

import SwiftUI
import WebKit
import AppKit

@available(macOS 15.4, *)
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

@available(macOS 15.4, *)
struct ExtensionActionButton: View {
    let ext: InstalledExtension
    @EnvironmentObject var browserManager: BrowserManager
    
    var body: some View {
        Button(action: {
            showExtensionPopup()
        }) {
            Group {
                if let iconPath = ext.iconPath,
                   let nsImage = NSImage(contentsOfFile: iconPath) {
                    Image(nsImage: nsImage)
                        .resizable()
                } else {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundColor(.blue)
                }
            }
            .frame(width: 20, height: 20)
            // Install an invisible anchor view for precise popup positioning
            .background(ActionAnchorView(extensionId: ext.id))
        }
        .buttonStyle(.plain)
        .help(ext.name)
    }
    
    private func showExtensionPopup() {
        print("🎯 Performing action for extension: \(ext.name)")
        
        // Get the native extension context
        guard let extensionContext = ExtensionManager.shared.getExtensionContext(for: ext.id) else {
            print("❌ No extension context found")
            return
        }
        
        // Use the PROPER way according to Apple docs: performAction
        // Pass the active tab when available so extensions relying on it (e.g., tabs.query) have context.
        print("✅ Calling performAction() - this should trigger the delegate")
        if let current = browserManager.tabManager.currentTab {
            // Use the stable cached adapter instead of creating a new one
            if let adapter = ExtensionManager.shared.stableAdapter(for: current) {
                extensionContext.performAction(for: adapter)
            } else {
                extensionContext.performAction(for: nil)
            }
        } else {
            extensionContext.performAction(for: nil) // fallback to default action
        }
    }
}

@available(macOS 15.4, *)
#Preview {
    ExtensionActionView(extensions: [])
}

// MARK: - Anchor View for Popover Positioning
private struct ActionAnchorView: NSViewRepresentable {
    let extensionId: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        if #available(macOS 15.4, *) {
            ExtensionManager.shared.setActionAnchor(for: extensionId, anchorView: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 15.4, *) {
            ExtensionManager.shared.setActionAnchor(for: extensionId, anchorView: nsView)
        }
    }
}
