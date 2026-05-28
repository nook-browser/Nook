//
//  ExtensionLibraryButton.swift
//  Nook
//

import SwiftUI
import AppKit
import os

@available(macOS 15.5, *)
struct ExtensionLibraryButton: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState

    private static let logger = Logger(subsystem: "com.nook.browser", category: "ExtensionLibraryButton")

    @State private var capturedWindow: NSWindow?
    @State private var anchorView: NSView?

    var body: some View {
        Button("Extensions", systemImage: "square.grid.2x2") {
            togglePanel()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(URLBarButtonStyle())
        .foregroundStyle(Color.primary)
        .background(ButtonAnchorCapture(window: $capturedWindow, anchorView: $anchorView))
        .onChange(of: windowState.isExtensionLibraryVisible) { _, visible in
            if !visible && panelController.isVisible {
                panelController.dismiss()
            }
        }
        .onChange(of: browserManager.currentTab(for: windowState)?.id) { _, _ in
            if panelController.isVisible {
                panelController.dismiss()
                windowState.isExtensionLibraryVisible = false
            }
        }
    }

    private var panelController: ExtensionLibraryPanelController {
        if windowState.extensionLibraryPanelController == nil {
            windowState.extensionLibraryPanelController = ExtensionLibraryPanelController()
        }
        return windowState.extensionLibraryPanelController!
    }

    private func togglePanel() {
        guard let window = capturedWindow ?? windowState.window,
              let settings = browserManager.nookSettings else {
            Self.logger.error("Early return — no window or settings")
            return
        }

        windowState.isExtensionLibraryVisible.toggle()

        if windowState.isExtensionLibraryVisible {
            // Get anchor frame from the button's parent view in window coordinates
            // The anchorView itself is zero-sized; its superview is the button's frame
            let anchor: CGRect
            if let view = anchorView, let superview = view.superview {
                let buttonFrame = superview.convert(superview.bounds, to: nil) // nil = window coordinates
                anchor = buttonFrame
            } else {
                // Last resort fallback
                let contentFrame = window.contentView?.bounds ?? window.frame
                anchor = CGRect(x: contentFrame.maxX - 50, y: contentFrame.maxY, width: 50, height: 40)
            }

            Self.logger.info("Opening panel — anchor=\(anchor.debugDescription, privacy: .public)")

            panelController.show(
                anchorFrame: anchor,
                in: window,
                browserManager: browserManager,
                windowState: windowState,
                settings: settings
            )
        } else {
            panelController.dismiss()
        }
    }
}

// MARK: - Button Anchor Capture

/// Captures the NSWindow and NSView from the SwiftUI view hierarchy for positioning.
private struct ButtonAnchorCapture: NSViewRepresentable {
    @Binding var window: NSWindow?
    @Binding var anchorView: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.setFrameSize(.zero)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.window = nsView.window
            self.anchorView = nsView
        }
    }
}
