//
//  BoostsWindowManager.swift
//  Nook
//
//  Created by Jude on 11/13/2025.
//

import AppKit
import SwiftUI
import WebKit

@MainActor
final class BoostsWindowManager: NSObject {
    static let shared = BoostsWindowManager()

    private var window: NSWindow?
    private weak var currentWebView: WKWebView?
    private var currentDomain: String?
    private var boostsManager: BoostsManager?

    private override init() {
        super.init()
    }

    func show(for webView: WKWebView, domain: String, boostsManager: BoostsManager) {
        self.currentWebView = webView
        self.currentDomain = domain
        self.boostsManager = boostsManager

        // Get existing boost or create new one
        let existingBoost = boostsManager.getBoost(for: domain)
        let config = existingBoost ?? BoostConfig()

        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 185, height: 600),
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.isMovableByWindowBackground = false
            win.backgroundColor = .clear
            win.isOpaque = false
            win.hasShadow = true
            win.level = .floating

            // Center the window on screen
            win.center()

            // Create SwiftUI hosting controller
            let hostingController = NSHostingController(
                rootView: BoostWindowContent(
                    config: config,
                    domain: domain,
                    onConfigChange: { [weak self] newConfig in
                        self?.applyBoost(newConfig)
                    },
                    onReset: { [weak self] in
                        self?.resetBoost()
                    },
                    onClose: { [weak self] in
                        self?.close()
                    }
                )
                .environmentObject(boostsManager)
            )

            win.contentViewController = hostingController
            window = win
        } else {
            // Recreate content with new config
            let hostingController = NSHostingController(
                rootView: BoostWindowContent(
                    config: config,
                    domain: domain,
                    onConfigChange: { [weak self] newConfig in
                        self?.applyBoost(newConfig)
                    },
                    onReset: { [weak self] in
                        self?.resetBoost()
                    },
                    onClose: { [weak self] in
                        self?.close()
                    }
                )
                .environmentObject(boostsManager)
            )

            window?.contentViewController = hostingController
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // Apply existing boost if available
        if let existingBoost = existingBoost {
            applyBoost(existingBoost)
        }
    }

    private func applyBoost(_ config: BoostConfig) {
        guard let webView = currentWebView,
            let domain = currentDomain,
            let manager = boostsManager
        else { return }

        // Save the boost config
        manager.saveBoost(config, for: domain)

        // Apply to webview
        manager.injectBoost(config, into: webView) { success in
            if success {
                print("✅ [BoostsWindowManager] Boost applied successfully")
            } else {
                print("❌ [BoostsWindowManager] Failed to apply boost")
            }
        }
    }

    private func resetBoost() {
        guard let webView = currentWebView,
            let domain = currentDomain,
            let manager = boostsManager
        else { return }

        // Remove saved boost
        manager.removeBoost(for: domain)

        // Disable DarkReader
        manager.disableBoost(in: webView) { success in
            if success {
                print("✅ [BoostsWindowManager] Boost disabled successfully")
            } else {
                print("❌ [BoostsWindowManager] Failed to disable boost")
            }
        }

        // Close the window
        close()
    }

    func close() {
        guard let window = self.window else { return }

        // Store references we need to clean up
        let windowToClose = window

        // Immediately nil out our reference to prevent reuse
        self.window = nil

        // Clear other references immediately (these are safe)
        self.currentWebView = nil
        self.currentDomain = nil

        // Delay the actual window closing and manager cleanup
        // This ensures the button's event handler completes before deallocation
        DispatchQueue.main.async { [weak self] in
            // First remove content view controller to break SwiftUI references
            windowToClose.contentViewController = nil

            // Small delay to let SwiftUI fully tear down
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                windowToClose.close()

                // Finally clear the manager reference
                self?.boostsManager = nil
            }
        }
    }
}

// MARK: - Window Content View

private struct BoostWindowContent: View {
    @State var config: BoostConfig
    let domain: String
    let onConfigChange: (BoostConfig) -> Void
    let onReset: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Custom header with close and reset buttons
            BoostWindowHeader(
                domain: domain,
                onReset: onReset,
                onClose: onClose
            )

            Rectangle()
                .fill(.black.opacity(0.07))
                .frame(height: 1)
                .frame(maxWidth: .infinity)

            // Main boost UI
            VStack(spacing: 15) {
                BoostColorPicker(
                    selectedColor: Binding(
                        get: { Color(hex: config.tintColor) },
                        set: { color in
                            config.tintColor = color.toHexString() ?? "#FF6B6B"
                            onConfigChange(config)
                        }
                    )
                )

                BoostOptions(
                    brightness: Binding(
                        get: { config.brightness },
                        set: {
                            config.brightness = $0
                            onConfigChange(config)
                        }
                    ),
                    contrast: Binding(
                        get: { config.contrast },
                        set: {
                            config.contrast = $0
                            onConfigChange(config)
                        }
                    ),
                    tintStrength: Binding(
                        get: { config.tintStrength },
                        set: {
                            config.tintStrength = $0
                            onConfigChange(config)
                        }
                    )
                )

                BoostFonts()
                BoostFontOptions()
                BoostZapButton(isActive: false)
                BoostCodeButton(isActive: false)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 36)
        }
        .frame(width: 185)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Custom Window Header

private struct BoostWindowHeader: View {
    let domain: String
    let onReset: () -> Void
    let onClose: () -> Void

    @State private var isXHovered: Bool = false
    @State private var isResetHovered: Bool = false
    @State private var isMenuHovered: Bool = false

    var body: some View {
        HStack {
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.black.opacity(isXHovered ? 0.4 : 0.3))
                    .animation(.default, value: isXHovered)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
            .onHover { state in
                isXHovered = state
            }

            Menu {
                Button("Rename this Boost...") {
                    // TODO: Implement rename
                }
                Button("Shuffle") {
                    // TODO: Implement shuffle colors
                }
                Button("Reset all edits") {
                    onReset()
                }
                Button("Delete this boost") {
                    onReset()
                }
                Divider()
                Button("All Boosts...") {
                    // TODO: Show all boosts list
                }
            } label: {
                HStack(spacing: 4) {
                    Text(domain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.black.opacity(0.45))
                }
            }
            .menuIndicator(.hidden)
            .background(isMenuHovered ? .black.opacity(0.07) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .onHover { state in
                isMenuHovered = state
            }

            Button {
                onReset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        .black.opacity(isResetHovered ? 0.4 : 0.3)
                    )
                    .animation(.default, value: isResetHovered)
            }
            .buttonStyle(PlainButtonStyle())
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
            .onHover { state in
                isResetHovered = state
            }
        }
        .frame(width: 185, height: 40)
        .background(BoostWindowDragView())
        .background(Color(hex: "F6F6F8"))
    }
}

// MARK: - Custom Drag View for Header Only

private struct BoostWindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableHeaderView {
        return DraggableHeaderView()
    }

    func updateNSView(_ nsView: DraggableHeaderView, context: Context) {}
}

private class DraggableHeaderView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        // Allow window dragging
        window?.performDrag(with: event)
    }
}
