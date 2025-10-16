//
//  TweakPanelView.swift
//  Nook
//
//  Simplified Tweak Panel for instant website customizations
//

import SwiftUI
import AppKit

struct TweakPanelView: View {
    @Binding var isVisible: Bool
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState

    // Panel position and dragging state
    @State private var panelPosition: CGPoint = CGPoint(x: 100, y: 100)
    @State private var isDragging: Bool = false
    @State private var dragOffset: CGSize = .zero

    // Tweak settings
    @State private var selectedFont: String = "system"
    @State private var selectedColor: String = "#000000"
    @State private var fontSize: FontSize = .medium
    @State private var textTransform: TextTransform = .normal
    @State private var brightness: Double = 1.0
    @State private var contrast: Double = 1.0
    @State private var saturation: Double = 1.0
    @State private var isDarkMode: Bool = false
    @State private var isZapModeActive: Bool = false
    @State private var showCodeEditor: Bool = false
    @State private var customCSS: String = ""
    @State private var customJS: String = ""

    // Available fonts
    private let availableFonts = [
        "System": "system",
        "Arial": "Arial, sans-serif",
        "Helvetica": "Helvetica, sans-serif",
        "Times": "Times, serif",
        "Courier": "Courier, monospace",
        "Georgia": "Georgia, serif",
        "Verdana": "Verdana, sans-serif",
        "Comic Sans": "Comic Sans MS, cursive"
    ]

    var body: some View {
        if isVisible {
            ZStack {
                // Main panel
                VStack(spacing: 0) {
                    // Header with drag handle
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("Tweak Panel")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)

                        Spacer()

                        // Close button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isVisible = false
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 18, height: 18)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.pointingHand.set()
                            } else {
                                NSCursor.arrow.set()
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.05))
                    .onTapGesture {
                        // Start dragging when header is tapped
                        isDragging = true
                    }

                    Divider()

                    // Main content
                    ScrollView {
                        VStack(spacing: 12) {
                            // Global Font Control
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Font")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primary)

                                Picker("Font", selection: $selectedFont) {
                                    ForEach(Array(availableFonts.keys.sorted()), id: \.self) { fontName in
                                        Text(fontName).tag(availableFonts[fontName]!)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(height: 24)
                                .onChange(of: selectedFont) { _, _ in
                                    applyTweaks()
                                }

                                // Size Control
                                HStack {
                                    Text("Size")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    HStack(spacing: 4) {
                                        ForEach(FontSize.allCases, id: \.self) { size in
                                            Button(action: {
                                                fontSize = size
                                                applyTweaks()
                                            }) {
                                                Text(size.displayText)
                                                    .font(.system(size: 9))
                                                    .foregroundColor(fontSize == size ? .white : .primary)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 4)
                                                            .fill(fontSize == size ? .blue : Color.clear)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }

                            Divider()

                            // Global Color Control
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Color")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primary)

                                HStack {
                                    // Color picker
                                    ColorPicker("", selection: Binding(
                                        get: { Color(hex: selectedColor) ?? .black },
                                        set: { color in
                                            selectedColor = color.toHexString() ?? "#000000"
                                            applyTweaks()
                                        }
                                    ))
                                    .frame(width: 30, height: 24)
                                    .clipped()

                                    // Hex input
                                    TextField("#000000", text: $selectedColor)
                                        .font(.system(size: 10, design: .monospaced))
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .onChange(of: selectedColor) { _, _ in
                                            applyTweaks()
                                        }
                                }

                                // Case Control
                                HStack {
                                    Text("Case")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    HStack(spacing: 4) {
                                        ForEach(TextTransform.allCases, id: \.self) { transform in
                                            Button(action: {
                                                textTransform = transform
                                                applyTweaks()
                                            }) {
                                                Text(transform.displayText)
                                                    .font(.system(size: 9))
                                                    .foregroundColor(textTransform == transform ? .white : .primary)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(
                                                        RoundedRectangle(cornerRadius: 4)
                                                            .fill(textTransform == transform ? .blue : Color.clear)
                                                    )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }

                            Divider()

                            // Visual Adjustments
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Visual")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.primary)

                                // Light/Dark toggle
                                HStack {
                                    Text("Theme")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Toggle("Dark Mode", isOn: $isDarkMode)
                                        .toggleStyle(SwitchToggleStyle())
                                        .controlSize(.mini)
                                        .onChange(of: isDarkMode) { _, _ in
                                            applyTweaks()
                                        }
                                }

                                // Brightness
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("Brightness")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(Int(brightness * 100))%")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    Slider(value: $brightness, in: 0.2...2.0, step: 0.1)
                                        .controlSize(.mini)
                                        .onChange(of: brightness) { _, _ in
                                            applyTweaks()
                                        }
                                }

                                // Contrast
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("Contrast")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(Int(contrast * 100))%")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    Slider(value: $contrast, in: 0.5...2.0, step: 0.1)
                                        .controlSize(.mini)
                                        .onChange(of: contrast) { _, _ in
                                            applyTweaks()
                                        }
                                }

                                // Saturation
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("Saturation")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(Int(saturation * 100))%")
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    Slider(value: $saturation, in: 0.0...2.0, step: 0.1)
                                        .controlSize(.mini)
                                        .onChange(of: saturation) { _, _ in
                                            applyTweaks()
                                        }
                                }
                            }

                            Divider()

                            // Action Buttons
                            HStack(spacing: 8) {
                                // Zap Mode button
                                Button(action: {
                                    isZapModeActive.toggle()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "bolt.fill")
                                            .font(.system(size: 10))
                                        Text("Zap")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .foregroundColor(isZapModeActive ? .white : .primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(isZapModeActive ? .orange : Color.secondary.opacity(0.2))
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("Click elements on the page to hide them")

                                // Code button
                                Button(action: {
                                    showCodeEditor.toggle()
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "curlybraces")
                                            .font(.system(size: 10))
                                        Text("Code")
                                            .font(.system(size: 10, weight: .medium))
                                    }
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.secondary.opacity(0.2))
                                    )
                                }
                                .buttonStyle(.plain)
                                .help("Add custom CSS/JavaScript")

                                Spacer()

                                // Reset button
                                Button(action: {
                                    resetTweaks()
                                }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, height: 24)
                                        .background(Color.secondary.opacity(0.1))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help("Reset all tweaks")
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                }
                .frame(width: 160, height: 480)
                .background(
                    BlurEffectView(material: .contentBackground, state: .active)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                )
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                .position(
                    x: panelPosition.x + dragOffset.width,
                    y: panelPosition.y + dragOffset.height
                )
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if isDragging {
                                dragOffset = value.translation
                            }
                        }
                        .onEnded { value in
                            panelPosition.x += value.translation.width
                            panelPosition.y += value.translation.height
                            dragOffset = .zero
                            isDragging = false

                            // Save position to UserDefaults
                            UserDefaults.standard.set(
                                CGPoint(x: panelPosition.x, y: panelPosition.y),
                                forKey: "tweakPanel.position"
                            )
                        }
                )
                .onAppear {
                    loadPanelState()
                }
                .onChange(of: isVisible) { _, newValue in
                    if newValue {
                        loadPanelState()
                    }
                }

                // Code editor sheet
                .sheet(isPresented: $showCodeEditor) {
                    CodeEditorView(
                        customCSS: $customCSS,
                        customJS: $customJS,
                        onApply: {
                            applyTweaks()
                            showCodeEditor = false
                        }
                    )
                }
            }
            .transition(.asymmetric(
                insertion: .scale(scale: 0.8).combined(with: .opacity),
                removal: .scale(scale: 0.8).combined(with: .opacity)
            ))
            .zIndex(1000)
        }
    }

    private func applyTweaks() {
        guard let currentTab = browserManager.currentTab(for: windowState),
              let webView = currentTab.webView else { return }

        // Generate CSS for all current tweaks
        let css = generateCSS()

        // Inject CSS into WebView
        let script = """
        (function() {
            // Remove existing tweak styles
            const existingStyle = document.getElementById('nook-tweak-panel-styles');
            if (existingStyle) {
                existingStyle.remove();
            }

            // Add new tweak styles
            const style = document.createElement('style');
            style.id = 'nook-tweak-panel-styles';
            style.textContent = `\(css.replacingOccurrences(of: "`", with: "\\`").replacingOccurrences(of: "${", with: "\\${"))`;
            document.head.appendChild(style);
        })();
        """

        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                print("🎨 [TweakPanel] Failed to apply tweaks: \(error)")
            }
        }

        // Save state to UserDefaults
        savePanelState()
    }

    private func generateCSS() -> String {
        var css = ""

        // Global font changes
        if selectedFont != "system" {
            css += """
            /* Global Font Override */
            * {
                font-family: \(selectedFont) !important;
            }
            """
        }

        // Font size
        css += """
        /* Font Size Override */
        * {
            font-size: \(fontSize.rawValue) !important;
        }
        """

        // Text color
        css += """
        /* Text Color Override */
        * {
            color: \(selectedColor) !important;
        }

        /* Preserve images and videos */
        img, video, canvas, svg {
            filter: none !important;
        }
        """

        // Text transformation
        if textTransform != .normal {
            css += """
            /* Text Transform Override */
            * {
                text-transform: \(textTransform.rawValue) !important;
            }
            """
        }

        // Visual adjustments
        var filters: [String] = []
        if brightness != 1.0 { filters.append("brightness(\(brightness))") }
        if contrast != 1.0 { filters.append("contrast(\(contrast))") }
        if saturation != 1.0 { filters.append("saturate(\(saturation))") }

        if !filters.isEmpty {
            let filterString = filters.joined(separator: " ")
            css += """
            /* Visual Adjustments */
            body * {
                filter: \(filterString) !important;
            }

            /* Preserve images and videos from filters */
            img, video, canvas, svg {
                filter: none !important;
            }
            """
        }

        // Dark mode
        if isDarkMode {
            css += """
            /* Dark Mode Override */
            body {
                background-color: #1a1a1a !important;
                background-image: none !important;
            }

            * {
                background-color: transparent !important;
                border-color: #444 !important;
            }

            /* Text adjustments for dark mode */
            body, p, div, span, h1, h2, h3, h4, h5, h6, li, td, th {
                color: #e0e0e0 !important;
            }

            /* Links */
            a {
                color: #4a9eff !important;
            }

            /* Preserve media */
            img, video, canvas, svg {
                filter: brightness(0.8) !important;
            }
            """
        }

        // Custom CSS
        if !customCSS.isEmpty {
            css += "\n/* Custom CSS */\n\(customCSS)\n"
        }

        return css
    }

    private func resetTweaks() {
        selectedFont = "system"
        selectedColor = "#000000"
        fontSize = .medium
        textTransform = .normal
        brightness = 1.0
        contrast = 1.0
        saturation = 1.0
        isDarkMode = false
        customCSS = ""
        customJS = ""

        // Clear all tweaks from WebView
        guard let currentTab = browserManager.currentTab(for: windowState),
              let webView = currentTab.webView else { return }

        let clearScript = """
        (function() {
            const style = document.getElementById('nook-tweak-panel-styles');
            if (style) {
                style.remove();
            }
        })();
        """

        webView.evaluateJavaScript(clearScript)
        savePanelState()
    }

    private func loadPanelState() {
        // Load position
        if let savedPosition = UserDefaults.standard.object(forKey: "tweakPanel.position") as? CGPoint {
            panelPosition = savedPosition
        }

        // Load tweak settings
        selectedFont = UserDefaults.standard.string(forKey: "tweakPanel.selectedFont") ?? "system"
        selectedColor = UserDefaults.standard.string(forKey: "tweakPanel.selectedColor") ?? "#000000"
        fontSize = FontSize(rawValue: UserDefaults.standard.string(forKey: "tweakPanel.fontSize") ?? "16px") ?? .medium
        textTransform = TextTransform(rawValue: UserDefaults.standard.string(forKey: "tweakPanel.textTransform") ?? "normal") ?? .normal
        brightness = UserDefaults.standard.double(forKey: "tweakPanel.brightness")
        contrast = UserDefaults.standard.double(forKey: "tweakPanel.contrast")
        saturation = UserDefaults.standard.double(forKey: "tweakPanel.saturation")
        isDarkMode = UserDefaults.standard.bool(forKey: "tweakPanel.isDarkMode")
        customCSS = UserDefaults.standard.string(forKey: "tweakPanel.customCSS") ?? ""
        customJS = UserDefaults.standard.string(forKey: "tweakPanel.customJS") ?? ""

        // Ensure default values for 0.0 cases
        if brightness == 0.0 { brightness = 1.0 }
        if contrast == 0.0 { contrast = 1.0 }
        if saturation == 0.0 { saturation = 1.0 }
    }

    private func savePanelState() {
        UserDefaults.standard.set(panelPosition, forKey: "tweakPanel.position")
        UserDefaults.standard.set(selectedFont, forKey: "tweakPanel.selectedFont")
        UserDefaults.standard.set(selectedColor, forKey: "tweakPanel.selectedColor")
        UserDefaults.standard.set(fontSize.rawValue, forKey: "tweakPanel.fontSize")
        UserDefaults.standard.set(textTransform.rawValue, forKey: "tweakPanel.textTransform")
        UserDefaults.standard.set(brightness, forKey: "tweakPanel.brightness")
        UserDefaults.standard.set(contrast, forKey: "tweakPanel.contrast")
        UserDefaults.standard.set(saturation, forKey: "tweakPanel.saturation")
        UserDefaults.standard.set(isDarkMode, forKey: "tweakPanel.isDarkMode")
        UserDefaults.standard.set(customCSS, forKey: "tweakPanel.customCSS")
        UserDefaults.standard.set(customJS, forKey: "tweakPanel.customJS")
    }
}

// MARK: - Supporting Types

enum FontSize: String, CaseIterable {
    case small = "14px"
    case medium = "16px"
    case large = "18px"
    case extraLarge = "20px"

    var displayText: String {
        switch self {
        case .small: return "S"
        case .medium: return "M"
        case .large: return "L"
        case .extraLarge: return "XL"
        }
    }
}

enum TextTransform: String, CaseIterable {
    case normal = "none"
    case uppercase = "uppercase"
    case lowercase = "lowercase"
    case capitalize = "capitalize"

    var displayText: String {
        switch self {
        case .normal: return "Normal"
        case .uppercase: return "UPPER"
        case .lowercase: return "lower"
        case .capitalize: return "Title"
        }
    }
}

// MARK: - Code Editor View

struct CodeEditorView: View {
    @Binding var customCSS: String
    @Binding var customJS: String
    let onApply: () -> Void

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Custom Code")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
                .buttonStyle(.plain)

                Button("Apply") {
                    onApply()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Tab view
            TabView {
                // CSS Editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom CSS")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal)

                    TextEditor(text: $customCSS)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(minHeight: 200)
                        .padding(.horizontal)
                }
                .tabItem {
                    Label("CSS", systemImage: "doc.text")
                }

                // JavaScript Editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom JavaScript")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal)

                    TextEditor(text: $customJS)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(minHeight: 200)
                        .padding(.horizontal)
                }
                .tabItem {
                    Label("JavaScript", systemImage: "doc.plaintext")
                }
            }
            .frame(width: 400, height: 300)
        }
        .frame(width: 400, height: 380)
    }
}