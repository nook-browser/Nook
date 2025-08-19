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
        // This will trigger the delegate method for popup presentation
        print("✅ Calling performAction() - this should trigger the delegate")
        extensionContext.performAction(for: nil) // nil = default action, not tab-specific
    }
}

@available(macOS 15.4, *)
#Preview {
    ExtensionActionView(extensions: [])
}