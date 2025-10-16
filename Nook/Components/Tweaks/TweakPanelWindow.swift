//
//  TweakPanelWindow.swift
//  Nook
//
//  Created by Claude Code on 16/10/2025.
//

import SwiftUI
import AppKit

class TweakPanelWindow: NSPanel {
    private var browserManager: BrowserManager?

    init(browserManager: BrowserManager) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 600),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        self.title = "Tweak Panel"
        self.titlebarAppearsTransparent = false
        self.titleVisibility = .visible

        // Make it float on top
        self.level = .floating

        // Make it not activate the app when shown
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]

        // Set minimum size
        self.minSize = NSSize(width: 200, height: 500)

        // Store browser manager reference
        self.browserManager = browserManager

        // Create the SwiftUI view with proper environment
        let tweakPanelContent = TweakPanelContentView(browserManager: browserManager)
        let hostingController = NSHostingController(rootView: tweakPanelContent)

        self.contentViewController = hostingController

        // Center the panel on screen initially
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelFrame = self.frame
            let x = screenFrame.midX - panelFrame.width / 2
            let y = screenFrame.midY - panelFrame.height / 2
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    override func close() {
        // Override to hide instead of close, so we can show it again later
        self.orderOut(nil)
    }

    func showPanel() {
        self.makeKeyAndOrderFront(nil)
        self.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.animator().alphaValue = 1.0
        }
    }

    func hidePanel() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.completionHandler = {
                self.orderOut(nil)
            }
            self.animator().alphaValue = 0.0
        }
    }
}

// MARK: - Tweak Panel Content View

struct TweakPanelContentView: View {
    let browserManager: BrowserManager

    // Tweak settings
    @State private var selectedFont: String = "system"
    @State private var selectedColor: String = "#000000"
    @State private var selectedUIColor: String = "#FFFFFF"
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
    @State private var showAppliedFeedback: Bool = false

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
        VStack(spacing: 0) {
            ScrollView {
                mainContent
            }
        }
        .frame(minWidth: 200, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            loadPanelState()
            applyTweaks() // Apply saved tweaks immediately when panel opens
        }
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
        .overlay(
            // Visual feedback overlay
            VStack {
                if showAppliedFeedback {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        Text("Applied")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.1))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else {
                    Spacer()
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showAppliedFeedback),
            alignment: .bottom
        )
    }

    private var mainContent: some View {
        VStack(spacing: 12) {
            fontControlSection
            Divider()
            textColorControlSection
            Divider()
            uiColorControlSection
            Divider()
            visualAdjustmentsSection
            Divider()
            actionButtonsSection
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private var fontControlSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Font")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)

            fontPicker
            fontSizeControl
        }
    }

    private var fontPicker: some View {
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
    }

    private var fontSizeControl: some View {
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

    private var textColorControlSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Text Color")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)

            HStack {
                textColorPicker
                textHexInput
            }
            caseControl
        }
    }

    private var textColorPicker: some View {
        ColorPicker("", selection: Binding(
            get: { Color(hex: selectedColor) ?? .black },
            set: { color in
                selectedColor = color.toHexString() ?? "#000000"
                applyTweaks()
            }
        ))
        .frame(width: 30, height: 24)
        .clipped()
    }

    private var textHexInput: some View {
        TextField("#000000", text: $selectedColor)
            .font(.system(size: 10, design: .monospaced))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .onChange(of: selectedColor) { _, _ in
                applyTweaks()
            }
    }

    private var caseControl: some View {
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

    private var uiColorControlSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UI Color")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)

            HStack {
                uiColorPicker
                uiHexInput
            }
        }
    }

    private var uiColorPicker: some View {
        ColorPicker("", selection: Binding(
            get: { Color(hex: selectedUIColor) ?? .white },
            set: { color in
                selectedUIColor = color.toHexString() ?? "#FFFFFF"
                applyTweaks()
            }
        ))
        .frame(width: 30, height: 24)
        .clipped()
    }

    private var uiHexInput: some View {
        TextField("#FFFFFF", text: $selectedUIColor)
            .font(.system(size: 10, design: .monospaced))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .onChange(of: selectedUIColor) { _, _ in
                applyTweaks()
            }
    }

    private var visualAdjustmentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Visual")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.primary)

            themeToggle
            brightnessControl
            contrastControl
            saturationControl
        }
    }

    private var themeToggle: some View {
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
    }

    private var brightnessControl: some View {
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
    }

    private var contrastControl: some View {
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
    }

    private var saturationControl: some View {
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

    private var actionButtonsSection: some View {
        HStack(spacing: 8) {
            zapModeButton
            codeButton
            Spacer()
            resetButton
        }
    }

    private var zapModeButton: some View {
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
    }

    private var codeButton: some View {
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
    }

    private var resetButton: some View {
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

    private func applyTweaks() {
        guard let currentTab = browserManager.currentTabForActiveWindow(),
              let activeWindowId = browserManager.activeWindowState?.id,
              let webView = browserManager.getWebView(for: currentTab.id, in: activeWindowId) else { return }

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
            } else {
                // Show visual feedback that tweaks were applied
                withAnimation(.easeInOut(duration: 0.3)) {
                    showAppliedFeedback = true
                }

                // Hide feedback after a short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showAppliedFeedback = false
                    }
                }
            }
        }

        // Save state to UserDefaults
        savePanelState()
    }

    // MARK: - Color Calculation Helpers

    private func blendColors(_ originalColor: String, with targetColor: String, intensity: Double) -> String {
        // Convert both colors to RGB
        let original = Color(hex: originalColor) ?? Color.black
        let target = Color(hex: targetColor) ?? Color.black

        let originalNSColor = NSColor(original)
        let targetNSColor = NSColor(target)

        guard let originalRGB = originalNSColor.usingColorSpace(.deviceRGB),
              let targetRGB = targetNSColor.usingColorSpace(.deviceRGB) else {
            return originalColor
        }

        var or: CGFloat = 0, og: CGFloat = 0, ob: CGFloat = 0, oa: CGFloat = 0
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0

        originalRGB.getRed(&or, green: &og, blue: &ob, alpha: &oa)
        targetRGB.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)

        // Blend colors: result = original * (1 - intensity) + target * intensity
        let r = or * (1.0 - intensity) + tr * intensity
        let g = og * (1.0 - intensity) + tg * intensity
        let b = ob * (1.0 - intensity) + tb * intensity

        // Convert back to hex
        let red = Int(round(r * 255))
        let green = Int(round(g * 255))
        let blue = Int(round(b * 255))

        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private func adjustColorBrightness(_ hexColor: String, by percentage: Double) -> String {
        // Create color directly from hex
        let color = Color(hex: hexColor) ?? Color.black
        let uiColor = NSColor(color)
        guard let rgbColor = uiColor.usingColorSpace(.deviceRGB) else { return hexColor }

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        rgbColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        // Adjust brightness
        red = min(1.0, max(0.0, red + CGFloat(percentage)))
        green = min(1.0, max(0.0, green + CGFloat(percentage)))
        blue = min(1.0, max(0.0, blue + CGFloat(percentage)))

        // Force 100% opacity
        alpha = 1.0

        // Convert back to hex (always opaque)
        let r = Int(round(red * 255))
        let g = Int(round(green * 255))
        let b = Int(round(blue * 255))

        return String(format: "#%02X%02X%02X", r, g, b)
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

        // Text color (separate from UI)
        css += """
        /* Text Color Override */
        * {
            color: \(selectedColor) !important;
        }
        """

        // Color transformation settings
        let baseUIColor = selectedUIColor
        let baseTextColor = selectedColor
        let tintIntensity: Double = 0.6 // How strongly we shift toward user colors (0.0 = original, 1.0 = full user color)

        // Color transformation CSS - preserves original hierarchy while applying theme
        css += """
        /* First, capture original colors by storing them */
        (function() {
            const style = document.createElement('style');
            style.id = 'nook-original-colors-capture';
            style.textContent = `
                /* Store original computed colors */
                * { --nook-original-bg: transparent; --nook-original-text: transparent; --nook-capture-done: 1; }
                body { --nook-original-bg: window.getComputedStyle(document.body).backgroundColor; }
                * {
                    var computed = window.getComputedStyle(this);
                    if (computed.backgroundColor && computed.backgroundColor !== 'rgba(0, 0, 0, 0)' && computed.backgroundColor !== 'transparent') {
                        this.style.setProperty('--nook-original-bg', computed.backgroundColor, 'important');
                    }
                    if (computed.color && computed.color !== 'rgba(0, 0, 0, 0)' && computed.color !== 'transparent') {
                        this.style.setProperty('--nook-original-text', computed.color, 'important');
                    }
                }
            `;
            document.head.appendChild(style);
        })();

        /* Apply color transformation with user theme */
        html, body {
            background-color: \(baseUIColor) !important;
        }

        /* Transform structural elements but exclude containers that directly contain media */
        div:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        section:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        article:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        header:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        footer:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        nav:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        main:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        aside:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        span:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        p:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        h1:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        h2:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        h3:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        h4:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        h5:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        h6:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        ul:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        ol:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        li:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        dl:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        dt:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        dd:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        table:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        tr:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        td:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        th:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        thead:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        tbody:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        tfoot:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        blockquote:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        pre:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        code:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        form:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        fieldset:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        legend:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        label:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        iframe:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        embed:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
        object:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)) {
            background-color: var(--nook-original-bg, \(baseUIColor)) !important;
        }

        /* Preserve media elements completely */
        img, video, canvas, svg, picture, source, track {
            background-color: transparent !important;
            filter: none !important;
        }

        /* Interactive elements - blend with theme */
        input, textarea, button, select, option, optgroup, datalist, output, progress, meter {
            background-color: var(--nook-original-bg, \(baseUIColor)) !important;
            border-color: \(isDarkMode ? "#FFFFFF" : "#000000") !important;
        }

        /* UI components - maintain original distinctions */
        .card, .panel, .widget, .module, .container, .box, .tile, .item, .component, .element, .block, .wrapper, .content, .section, .area, .region, .zone, .cell, .grid, .list, .row, .column, .group, .set, .collection {
            background-color: var(--nook-original-bg, \(baseUIColor)) !important;
        }

        /* Additional UI patterns */
        .sidebar, .menu, .nav, .toolbar, .bar, .header, .footer, .banner, .hero, .section, .segment, .module, .widget, .portlet, .gadget, applet, frame {
            background-color: var(--nook-original-bg, \(baseUIColor)) !important;
        }

        /* Transform text colors with theme */
        * {
            color: var(--nook-original-text, \(baseTextColor)) !important;
        }

        /* Links maintain distinction but get theme influence */
        a, a:visited, a:hover, a:active {
            color: var(--nook-original-text, \(baseTextColor)) !important;
        }

        /* Preserve media */
        img, video, canvas, svg, picture, source, track {
            filter: none !important;
            background-color: transparent !important;
        }

        /* Apply color transformations after capturing originals */
        setTimeout(() => {
            const intensity = \(tintIntensity);
            const targetBg = '\(baseUIColor)';
            const targetText = '\(baseTextColor)';

            // Transform background colors
            document.querySelectorAll('[style*="--nook-original-bg"]').forEach(el => {
                const original = el.style.getPropertyValue('--nook-original-bg');
                if (original && original !== 'transparent') {
                    const blended = blendColors(original, targetBg, intensity);
                    el.style.backgroundColor = blended;
                }
            });

            // Transform text colors
            document.querySelectorAll('[style*="--nook-original-text"]').forEach(el => {
                const original = el.style.getPropertyValue('--nook-original-text');
                if (original && original !== 'transparent') {
                    const blended = blendColors(original, targetText, intensity);
                    el.style.color = blended;
                }
            });
        }, 100);

        // Color blending helper function
        function blendColors(original, target, intensity) {
            const rgb = (color) => {
                const result = color.match(/\\d+/g);
                return result ? result.map(Number) : [0, 0, 0];
            };

            const [or, og, ob] = rgb(original);
            const [tr, tg, tb] = rgb(target);

            const r = Math.round(or * (1 - intensity) + tr * intensity);
            const g = Math.round(og * (1 - intensity) + tg * intensity);
            const b = Math.round(ob * (1 - intensity) + tb * intensity);

            return `rgb(${r}, ${g}, ${b})`;
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

        // Dark mode override using same colors
        if isDarkMode {
            let darkBaseColor = selectedUIColor
            let darkContentColor = adjustColorBrightness(darkBaseColor, by: -0.05)
            let darkComponentColor = adjustColorBrightness(darkBaseColor, by: -0.15)
            let darkInteractiveColor = adjustColorBrightness(darkBaseColor, by: -0.1)

            css += """
            /* Dark Mode Override - Using Same Colors */
            html, body {
                background-color: \(darkBaseColor) !important;
                background-image: none !important;
            }

            /* Force dark backgrounds but exclude containers that directly contain media */
            div:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            section:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            article:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            header:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            footer:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            nav:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            main:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            aside:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            span:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            p:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            h1:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            h2:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            h3:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            h4:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            h5:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            h6:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            ul:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            ol:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            li:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            dl:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            dt:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            dd:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            table:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            tr:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            td:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            th:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            thead:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            tbody:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            tfoot:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            blockquote:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            pre:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            code:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            form:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            fieldset:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            legend:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            label:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            iframe:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            embed:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)),
            object:not(:has(img)):not(:has(video)):not(:has(canvas)):not(:has(svg)):not(:has(picture)) {
                background-color: \(darkContentColor) !important;
            }

            /* Preserve media elements in dark mode */
            img, video, canvas, svg, picture, source, track {
                background-color: transparent !important;
            }

            /* Dark UI components */
            .card, .panel, .widget, .module, .container, .box, .tile, .item, .component, .element, .block, .wrapper, .content, .section, .area, .region, .zone, .cell, .grid, .list, .row, .column, .group, .set, .collection {
                background-color: \(darkComponentColor) !important;
                border-color: \(adjustColorBrightness(darkBaseColor, by: -0.25)) !important;
            }

            /* Dark additional UI patterns */
            .sidebar, .menu, .nav, .toolbar, .bar, .header, .footer, .banner, .hero, .section, .segment, .module, .widget, .portlet, .gadget, applet, frame {
                background-color: \(darkComponentColor) !important;
                border-color: \(adjustColorBrightness(darkBaseColor, by: -0.2)) !important;
            }

            /* Dark interactive elements */
            input, textarea, button, select, option, optgroup, datalist, output, progress, meter {
                background-color: \(darkInteractiveColor) !important;
                border-color: \(adjustColorBrightness(darkBaseColor, by: -0.2)) !important;
                color: \(selectedColor) !important;
            }

            /* Removed problematic universal background application */

            /* Ensure text visibility in dark mode */
            body, p, div, span, h1, h2, h3, h4, h5, h6, li, td, th, strong, em, b, i, u, s, strike {
                color: \(selectedColor) !important;
            }

            /* Links use text color with underline */
            a, a:visited, a:hover, a:active {
                color: \(selectedColor) !important;
                text-decoration: underline !important;
            }

            /* Media adjustment for dark mode */
            img, video, canvas, svg, picture, source, track {
                filter: brightness(0.7) contrast(1.3) !important;
                background-color: transparent !important;
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
        selectedUIColor = "#FFFFFF"
        fontSize = .medium
        textTransform = .normal
        brightness = 1.0
        contrast = 1.0
        saturation = 1.0
        isDarkMode = false
        customCSS = ""
        customJS = ""

        // Clear all tweaks from WebView
        guard let currentTab = browserManager.currentTabForActiveWindow(),
              let activeWindowId = browserManager.activeWindowState?.id,
              let webView = browserManager.getWebView(for: currentTab.id, in: activeWindowId) else { return }

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
        // Load tweak settings
        selectedFont = UserDefaults.standard.string(forKey: "tweakPanel.selectedFont") ?? "system"
        selectedColor = UserDefaults.standard.string(forKey: "tweakPanel.selectedColor") ?? "#000000"
        selectedUIColor = UserDefaults.standard.string(forKey: "tweakPanel.selectedUIColor") ?? "#FFFFFF"
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
        UserDefaults.standard.set(selectedFont, forKey: "tweakPanel.selectedFont")
        UserDefaults.standard.set(selectedColor, forKey: "tweakPanel.selectedColor")
        UserDefaults.standard.set(selectedUIColor, forKey: "tweakPanel.selectedUIColor")
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

