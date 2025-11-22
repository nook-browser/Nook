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
    private var codeEditorWindow: NSWindow?
    private weak var parentWindow: NSWindow?
    weak var currentWebView: WKWebView?
    private var currentDomain: String?
    var boostsManager: BoostsManager?

    private override init() {
        super.init()
    }

    func show(for webView: WKWebView, domain: String, boostsManager: BoostsManager) {
        self.currentWebView = webView
        self.currentDomain = domain
        self.boostsManager = boostsManager
        
        self.parentWindow = webView.window

        let existingBoost = boostsManager.getBoost(for: domain)
        let config = existingBoost ?? BoostConfig()

        if window == nil {
            let win = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 185, height: 600),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            win.titleVisibility = .hidden
            win.titlebarAppearsTransparent = true
            win.isMovableByWindowBackground = true
            win.backgroundColor = .clear
            win.isOpaque = false
            win.hasShadow = true
            win.level = .normal
            win.hidesOnDeactivate = false
            win.isReleasedWhenClosed = false
            win.standardWindowButton(.closeButton)?.isHidden = true
            win.standardWindowButton(.miniaturizeButton)?.isHidden = true
            win.standardWindowButton(.zoomButton)?.isHidden = true

            if let parentWindow = self.parentWindow {
                let parentFrame = parentWindow.frame
                let xPos = parentFrame.maxX - 185 - 20
                let yPos = parentFrame.maxY - 600 - 60
                win.setFrameOrigin(NSPoint(x: xPos, y: yPos))
            } else {
                win.center()
            }

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

        if let parentWindow = self.parentWindow, let window = self.window {
            window.parent?.removeChildWindow(window)
            parentWindow.addChildWindow(window, ordered: .above)
        }
        
        window?.makeKeyAndOrderFront(nil)

        if let existingBoost = existingBoost {
            applyBoost(existingBoost)
        }
    }

    private func applyBoost(_ config: BoostConfig) {
        guard let webView = currentWebView,
            let domain = currentDomain,
            let manager = boostsManager
        else { return }

        manager.saveBoost(config, for: domain)

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

        manager.removeBoost(for: domain)

        manager.disableBoost(in: webView) { success in
            if success {
                print("✅ [BoostsWindowManager] Boost disabled successfully")
            } else {
                print("❌ [BoostsWindowManager] Failed to disable boost")
            }
        }
        
        manager.applyPageZoom(100, to: webView)
        manager.injectCSS("", into: webView)
        manager.injectJavaScript("", into: webView) { _ in }

        close()
    }

    func close() {
        guard let window = self.window else { return }

        let windowToClose = window
        let parent = self.parentWindow

        self.window = nil
        self.currentWebView = nil
        self.currentDomain = nil
        self.parentWindow = nil

        DispatchQueue.main.async { [weak self] in
            if let parent = parent {
                parent.removeChildWindow(windowToClose)
            }
            
            windowToClose.contentViewController = nil

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                windowToClose.close()
                self?.boostsManager = nil
            }
        }
    }
    
    func showCodeEditor(for config: Binding<BoostConfig>, onConfigChange: @escaping (BoostConfig) -> Void) {
        closeCodeEditor()
        
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.level = .normal
        win.hidesOnDeactivate = false
        win.isReleasedWhenClosed = false
        win.standardWindowButton(.closeButton)?.isHidden = true
        win.standardWindowButton(.miniaturizeButton)?.isHidden = true
            win.standardWindowButton(.zoomButton)?.isHidden = true
        
        if let parentWindow = self.parentWindow {
            let parentFrame = parentWindow.frame
            let xPos = parentFrame.midX - 240
            let yPos = parentFrame.midY - 300
            win.setFrameOrigin(NSPoint(x: xPos, y: yPos))
        } else {
            win.center()
        }
        
        let hostingController = NSHostingController(
            rootView: CodeEditorContentView(
                config: config,
                onConfigChange: onConfigChange,
                onClose: { [weak self] in
                    self?.closeCodeEditor()
                }
            )
        )
        
        win.contentViewController = hostingController
        codeEditorWindow = win
        
        if let parentWindow = self.parentWindow {
            parentWindow.addChildWindow(win, ordered: .above)
        }
        
        win.makeKeyAndOrderFront(nil)
    }
    
    func closeCodeEditor() {
        guard let window = codeEditorWindow else { return }
        
        let windowToClose = window
        let parent = self.parentWindow
        
        codeEditorWindow = nil
        
        DispatchQueue.main.async {
            if let parent = parent {
                parent.removeChildWindow(windowToClose)
            }
            
            windowToClose.contentViewController = nil
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                windowToClose.close()
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
    
    @State private var isZapActive: Bool = false
    @EnvironmentObject var boostsManager: BoostsManager

    var body: some View {
        VStack(spacing: 0) {
            // Custom header with close and reset buttons
            BoostWindowHeader(
                config: $config,
                defaultDomain: domain,
                onConfigChange: onConfigChange,
                onReset: onReset,
                onClose: onClose
            )

            Rectangle()
                .fill(.black.opacity(0.07))
                .frame(height: 1)
                .frame(maxWidth: .infinity)

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
                    ),
                    mode: Binding(
                        get: { config.mode },
                        set: {
                            config.mode = $0
                            onConfigChange(config)
                        }
                    )
                )

                BoostFonts(config: $config, onConfigChange: onConfigChange)
                BoostFontOptions(config: $config, onConfigChange: onConfigChange)
                BoostZapButton(
                    isActive: $isZapActive,
                    onClick: {
                        let zapScript = """
                            (function() {
                                const adSelectors = [
                                    '[class*="ad"]',
                                    '[id*="ad"]',
                                    '[class*="advertisement"]',
                                    '[id*="advertisement"]',
                                    'iframe[src*="ads"]',
                                    'iframe[src*="advertisement"]'
                                ];
                                
                                adSelectors.forEach(selector => {
                                    try {
                                        document.querySelectorAll(selector).forEach(el => el.remove());
                                    } catch(e) {}
                                });
                                
                                const adClasses = ['ad', 'ads', 'advertisement', 'ad-banner', 'ad-container'];
                                adClasses.forEach(className => {
                                    try {
                                        document.querySelectorAll('.' + className).forEach(el => el.remove());
                                    } catch(e) {}
                                });
                                
                                console.log('✅ [Nook Boost] Zap applied - ads removed');
                            })();
                            """
                        
                        if let webView = BoostsWindowManager.shared.currentWebView,
                           let manager = BoostsWindowManager.shared.boostsManager {
                            manager.injectJavaScript(zapScript, into: webView) { success in
                                if success {
                                    print("✅ [BoostsWindowManager] Zap script injected")
                                }
                            }
                        }
                    }
                )
                BoostCodeButton(
                    isActive: false,
                    onClick: {
                        BoostsWindowManager.shared.showCodeEditor(
                            for: Binding(
                                get: { config },
                                set: { newConfig in
                                    config = newConfig
                                    onConfigChange(newConfig)
                                }
                            ),
                            onConfigChange: onConfigChange
                        )
                    }
                )
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 36)
            .background(NonDraggableArea())
        }
        .frame(width: 185)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Custom Window Header

private struct BoostWindowHeader: View {
    @Binding var config: BoostConfig
    let defaultDomain: String
    let onConfigChange: (BoostConfig) -> Void
    let onReset: () -> Void
    let onClose: () -> Void
    
    private var displayDomain: String {
        config.customName ?? defaultDomain
    }
    
    @State private var isXHovered: Bool = false
    @State private var isResetHovered: Bool = false
    @State private var isMenuHovered: Bool = false
    @State private var showRenameDialog: Bool = false
    @State private var renameText: String = ""
    @EnvironmentObject var boostsManager: BoostsManager

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
                    renameText = config.customName ?? defaultDomain
                    showRenameDialog = true
                }
                Button("Shuffle") {
                    // Generate random hex color
                    let colors = ["#FF6B6B", "#4ECDC4", "#45B7D1", "#FFA07A", "#98D8C8", "#F7DC6F", "#BB8FCE", "#85C1E2", "#F8B739", "#E74C3C"]
                    config.tintColor = colors.randomElement() ?? "#FF6B6B"
                    onConfigChange(config)
                }
                Button("Reset all edits") {
                    onReset()
                }
                Button("Delete this boost") {
                    onReset()
                }
                Divider()
                Button("All Boosts...") {
                    // Show all boosts - for now just print them
                    let allBoosts = boostsManager.boosts.keys.sorted()
                    print("📋 [BoostsWindowManager] All boosts: \(allBoosts.joined(separator: ", "))")
                    // TODO: Show in a dialog or window
                }
            } label: {
                HStack(spacing: 4) {
                    Text(displayDomain)
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
            .popover(isPresented: $showRenameDialog, arrowEdge: .bottom) {
                VStack(spacing: 12) {
                    Text("Rename Boost")
                        .font(.system(size: 14, weight: .semibold))
                    TextField("Boost name", text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                    HStack(spacing: 8) {
                        Button("Cancel") {
                            showRenameDialog = false
                        }
                        .buttonStyle(.bordered)
                        Button("Save") {
                            config.customName = renameText.isEmpty ? nil : renameText
                            onConfigChange(config)
                            showRenameDialog = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
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
        .background(Color(hex: "F6F6F8"))
    }
}

// MARK: - Non-draggable content wrapper

private struct NonDraggableArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NonDraggableNSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class NonDraggableNSView: NSView {
    override var mouseDownCanMoveWindow: Bool {
        return false
    }
}

// MARK: - Code Editor Content View

private struct CodeEditorContentView: View {
    @Binding var config: BoostConfig
    var onConfigChange: (BoostConfig) -> Void
    var onClose: () -> Void
    
    @State private var cssCode: String
    @State private var jsCode: String
    @State private var selectedLanguage: Language = .css
    
    init(config: Binding<BoostConfig>, onConfigChange: @escaping (BoostConfig) -> Void, onClose: @escaping () -> Void) {
        self._config = config
        self.onConfigChange = onConfigChange
        self.onClose = onClose
        self._cssCode = State(initialValue: config.wrappedValue.customCSS)
        self._jsCode = State(initialValue: config.wrappedValue.customJS)
    }
    
    var body: some View {
        CodeEditor(
            cssCode: $cssCode,
            jsCode: $jsCode,
            selectedLanguage: $selectedLanguage,
            onBack: onClose,
            onRefresh: {
                config.customCSS = cssCode
                config.customJS = jsCode
                onConfigChange(config)
                
                if let webView = BoostsWindowManager.shared.currentWebView,
                   let manager = BoostsWindowManager.shared.boostsManager {
                    if !cssCode.isEmpty {
                        manager.injectCSS(cssCode, into: webView)
                    }
                    if !jsCode.isEmpty {
                        manager.injectJavaScript(jsCode, into: webView) { _ in }
                    }
                }
            }
        )
        .frame(width: 480, height: 600)
    }
}

