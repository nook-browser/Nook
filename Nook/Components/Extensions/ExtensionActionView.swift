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
        .onReceive(NotificationCenter.default.publisher(for: .extensionActionUpdated)) { notification in
            // Update if this is for our extension
            if let userInfo = notification.userInfo,
               let updatedExtensionId = userInfo["extensionId"] as? String,
               updatedExtensionId == ext.id {
                updateActionState()
            }
        }
    }
    
    private func showExtensionPopup() {
        print("🎯 Performing action for extension: \(ext.name)")

        guard let extensionContext = ExtensionManager.shared.getExtensionContext(for: ext.id) else {
            print("⚠️ [ExtensionActionView] No extension context found - extension may not be properly loaded")

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Extension Not Available"
                alert.informativeText = "The extension '\(self.ext.name)' is not currently loaded or has been disabled."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
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
        guard let _ = ExtensionManager.shared.getExtensionContext(for: ext.id) else {
            print("⚠️ [ExtensionActionView] No extension context found for action state update - extension may be disabled")

            DispatchQueue.main.async {
                self.badgeText = ""
                self.badgeBackgroundColor = NSColor.systemGray
                self.badgeTextColor = NSColor.white
                self.isActionEnabled = false
            }
            return
        }

        // Get the action state from ExtensionManager
        if #available(macOS 15.4, *) {
            let state = ExtensionManager.shared.getActionState(for: ext.id)
            
            Task { @MainActor in
                // Update badge properties from actual state
                self.badgeText = state.badgeText
                
                // Convert color arrays to NSColor
                self.badgeBackgroundColor = NSColor(
                    red: state.badgeBackgroundColor[0],
                    green: state.badgeBackgroundColor[1],
                    blue: state.badgeBackgroundColor[2],
                    alpha: state.badgeBackgroundColor[3]
                )
                
                self.badgeTextColor = NSColor(
                    red: state.badgeTextColor[0],
                    green: state.badgeTextColor[1],
                    blue: state.badgeTextColor[2],
                    alpha: state.badgeTextColor[3]
                )
                
                self.isActionEnabled = state.isEnabled

                print("🔧 Updated action state for \(ext.name): badge='\(self.badgeText)', enabled=\(self.isActionEnabled)")
            }
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
