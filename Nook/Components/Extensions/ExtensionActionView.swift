//
//  ExtensionActionView.swift
//  Nook
//
//  Clean ExtensionActionView using ONLY native WKWebExtension APIs
//

import SwiftUI
import WebKit
import AppKit

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
    @State private var badgeText: String = ""
    @State private var badgeBackgroundColor: NSColor = .clear
    @State private var badgeTextColor: NSColor = .white
    @State private var isActionEnabled: Bool = true

    var body: some View {
        Button(action: {
            showExtensionPopup()
        }) {
            ZStack(alignment: .topTrailing) {
                // Main icon
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
                .opacity(isActionEnabled ? 1.0 : 0.5)

                // Badge overlay
                if !badgeText.isEmpty {
                    Text(badgeText)
                        .font(.caption2)
                        .foregroundColor(Color(badgeTextColor))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(badgeBackgroundColor))
                        )
                        .offset(x: 2, y: -2)
                }
            }
            .background(ActionAnchorView(extensionId: ext.id))
        }
        .buttonStyle(.plain)
        .disabled(!isActionEnabled)
        .help(ext.name + (!badgeText.isEmpty ? " - \(badgeText)" : ""))
        .onAppear {
            updateActionState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            updateActionState()
        }
    }
    
    private func showExtensionPopup() {
        print("🎯 Performing action for extension: \(ext.name)")

        guard let extensionContext = ExtensionManager.shared.getExtensionContext(for: ext.id) else {
            print("❌ No extension context found")
            return
        }

        // Ensure the extension context has proper permissions for action
        extensionContext.setPermissionStatus(.grantedExplicitly, for: .activeTab)
        extensionContext.setPermissionStatus(.grantedExplicitly, for: .scripting)

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

    private func updateActionState() {
        guard ExtensionManager.shared.getExtensionContext(for: ext.id) != nil else {
            print("❌ No extension context found for action state update")
            return
        }

        // Get the action from the extension context
        // Note: WKWebExtension.Action properties are limited in current SDK
        // We'll use placeholder implementations for missing properties

        Task { @MainActor in
            // Update badge properties (using placeholder values for now)
            self.badgeText = "" // placeholder - action.badgeText not available
            self.badgeBackgroundColor = NSColor.systemBlue // placeholder - action.badgeBackgroundColor not available
            self.badgeTextColor = NSColor.white // placeholder - action.badgeTextColor not available
            self.isActionEnabled = true // placeholder - action.isEnabled not available

            print("🔧 Updated action state for \(ext.name): badge='\(self.badgeText)', enabled=\(self.isActionEnabled)")
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
