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
    @StateObject private var windowState = BrowserWindowState()
    
    var body: some View {
        WindowView()
            .environmentObject(windowState)
            .environmentObject(browserManager.gradientColorManager)
            .background(WindowFocusBridge(windowState: windowState, browserManager: browserManager))
            .frame(minWidth: 470, minHeight: 382)
            .onAppear {
                // Register this window state with the browser manager
                browserManager.registerWindowState(windowState)
            }
            .onDisappear {
                // Unregister this window state when the window closes
                browserManager.unregisterWindowState(windowState.id)
            }
    }
}

private struct WindowFocusBridge: NSViewRepresentable {
    let windowState: BrowserWindowState
    unowned let browserManager: BrowserManager
    
    func makeCoordinator() -> Coordinator {
        Coordinator(windowState: windowState, browserManager: browserManager)
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
        weak var browserManager: BrowserManager?
        private weak var window: NSWindow?
        private var keyObserver: Any?

        init(windowState: BrowserWindowState, browserManager: BrowserManager) {
            self.windowState = windowState
            self.browserManager = browserManager
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
                    self.browserManager?.setActiveWindowState(self.windowState)
                }
            }

            if window.isKeyWindow {
                Task { @MainActor in
                    browserManager?.setActiveWindowState(windowState)
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
