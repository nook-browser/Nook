//
//  ContentView.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(WindowRegistry.self) private var windowRegistry
    @State private var windowState = BrowserWindowState()
    @State private var commandPalette = CommandPaletteState()

    var body: some View {
        WindowView()
            .environment(windowState)
            .environment(commandPalette)
            .environmentObject(browserManager.gradientColorManager)
            .focusedValue(\.commandPalette, commandPalette)
            .background(WindowFocusBridge(windowState: windowState, windowRegistry: windowRegistry))
            .frame(minWidth: 470, minHeight: 382)
            .onAppear {
                // Set TabManager reference for computed properties
                windowState.tabManager = browserManager.tabManager
                // Set CommandPalette reference for global shortcuts
                windowState.commandPalette = commandPalette
                // Register this window state with the registry
                windowRegistry.register(windowState)
            }
            .onDisappear {
                // Unregister this window state when the window closes
                windowRegistry.unregister(windowState.id)
            }
    }
}

private struct WindowFocusBridge: NSViewRepresentable {
    let windowState: BrowserWindowState
    let windowRegistry: WindowRegistry

    func makeCoordinator() -> Coordinator {
        Coordinator(windowState: windowState, windowRegistry: windowRegistry)
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.attach(to: view.window)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.attach(to: nsView.window)
        }
    }
    
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        let windowState: BrowserWindowState
        let windowRegistry: WindowRegistry
        private weak var window: NSWindow?
        private var keyObserver: Any?

        init(windowState: BrowserWindowState, windowRegistry: WindowRegistry) {
            self.windowState = windowState
            self.windowRegistry = windowRegistry
        }

        func attach(to window: NSWindow?) {
            guard self.window !== window else { return }
            detach()
            self.window = window
            guard let window else { return }

            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.windowRegistry.setActive(self.windowState)
                }
            }

            if window.isKeyWindow {
                Task { @MainActor in
                    windowRegistry.setActive(windowState)
                }
            }
        }

        func detach() {
            if let observer = keyObserver {
                NotificationCenter.default.removeObserver(observer)
                keyObserver = nil
            }
            window = nil
        }

        deinit {
            detach()
        }
    }
}
