//
//  PulseApp.swift
//  Pulse
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

@main
struct PulseApp: App {
    @StateObject private var browserManager = BrowserManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(BackgroundWindowModifier())
                .ignoresSafeArea(.all)
                .environmentObject(browserManager)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            PulseCommands(browserManager: browserManager)
        }

    }
}

struct PulseCommands: Commands {
    let browserManager: BrowserManager

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    var body: some Commands {
        // Sidebar commands
        CommandGroup(after: .sidebar) {
            Button("Toggle Sidebar") {
                browserManager.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: .command)
        }

        // Navigation commands
        CommandGroup(after: .toolbar) {

            Divider()

            // Future shortcuts can go here
            Button("New Tab") {
                browserManager.createNewTab()
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
            .disabled(true)  // Enable when implemented

            Divider()
        }

        // View commands
        CommandGroup(after: .windowSize) {
            Button("Focus URL Bar") {
                browserManager.focusURLBar()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(true)  // Enable when implemented
        }
        
        // File Section
        CommandGroup(replacing: .saveItem) {
            Button("New Tab...") {
                browserManager.openCommandPalette()
            }
            .keyboardShortcut("t", modifiers: .command)
            Button("New Window") {
                browserManager.openCommandPalette()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("Close Tab") {
                browserManager.closeCurrentTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(browserManager.tabManager.tabs.isEmpty)

        }
    }
}

struct BackgroundWindowModifier: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.toolbar?.isVisible = false
                window.titlebarAppearsTransparent = true
                window.backgroundColor = .clear
                window.titleVisibility = .hidden
                window.isReleasedWhenClosed = false
                window.isMovableByWindowBackground = false
                window.isMovable = false
                window.styleMask = [
                    .titled, .closable, .miniaturizable, .resizable,
                    .fullSizeContentView,
                ]

                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {

    }
}
