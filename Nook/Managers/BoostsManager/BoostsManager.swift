//
//  BoostsManager.swift
//  Nook
//
//  Created by Jude on 11/11/2025.
//

import SwiftUI
import WebKit

struct BoostConfig: Codable, Equatable {
    var brightness: Int = 100
    var contrast: Int = 90
    var sepia: Int = 0
    var mode: Int = 1
    var tintColor: String = "#FF6B6B"
    var tintStrength: Int = 30
    var customCSS: String = ""
    var customJS: String = ""
    var fontFamily: String? = nil
    var pageZoom: Int = 100
    var textTransform: String = "none"
    var customName: String? = nil
}

@MainActor
class BoostsManager: ObservableObject {
    @Published private(set) var boosts: [String: BoostConfig] = [:]
    
    private let userDefaults = UserDefaults.standard
    private let boostsKey = "nook_domain_boosts"
    
    // Cache for boost user scripts to avoid regeneration
    // Key: domain:configHash, Value: array of scripts [fontScript (optional), mainBoostScript]
    private var scriptCache: [String: [WKUserScript]] = [:]
    
    init() {
        loadBoosts()
    }

    // MARK: - Public Methods

    /// Check if a domain has a boost configured
    func hasBoost(for domain: String) -> Bool {
        let normalizedDomain = normalizeDomain(domain)
        return boosts[normalizedDomain] != nil
    }

    /// Get boost configuration for a domain
    func getBoost(for domain: String) -> BoostConfig? {
        let normalizedDomain = normalizeDomain(domain)
        return boosts[normalizedDomain]
    }

    /// Save a boost configuration for a domain
    func saveBoost(_ config: BoostConfig, for domain: String) {
        let normalizedDomain = normalizeDomain(domain)
        
        // Remove all cached scripts for this domain (old configs)
        // This forces regeneration with new config
        let keysToRemove = scriptCache.keys.filter { $0.hasPrefix("\(normalizedDomain):") }
        for key in keysToRemove {
            scriptCache.removeValue(forKey: key)
        }
        
        boosts[normalizedDomain] = config
        persistBoosts()
    }

    /// Remove boost for a domain
    func removeBoost(for domain: String) {
        let normalizedDomain = normalizeDomain(domain)
        
        let keysToRemove = scriptCache.keys.filter { $0.hasPrefix("\(normalizedDomain):") }
        for key in keysToRemove {
            scriptCache.removeValue(forKey: key)
        }
        
        boosts.removeValue(forKey: normalizedDomain)
        persistBoosts()
    }

    /// Create cache key for boost script
    private func cacheKey(for config: BoostConfig, domain: String) -> String {
        let normalizedDomain = normalizeDomain(domain)
        let configHash = "\(config.brightness)-\(config.contrast)-\(config.tintColor)-\(config.fontFamily ?? "nil")-\(config.pageZoom)-\(config.textTransform)-\(config.customCSS.hashValue)-\(config.customJS.hashValue)"
        return "\(normalizedDomain):\(configHash)"
    }
    
    /// Create WKUserScript(s) for boost injection (to be added at document start)
    /// Uses caching to avoid regenerating scripts on every navigation
    /// Fonts are injected via DarkReader's native API (useFont + fontFamily) for instant application
    /// Returns array with single script: [mainBoostScript]
    func createBoostUserScripts(for config: BoostConfig, domain: String) -> [WKUserScript] {
        let key = cacheKey(for: config, domain: domain)
        
        if let cachedScripts = scriptCache[key] {
            print("✅ [BoostsManager] Using cached boost scripts for: \(domain) (\(cachedScripts.count) scripts)")
            return cachedScripts
        }
        
        guard let scriptPath = Bundle.main.path(forResource: "darkreader", ofType: "js"),
            let darkreaderSource = try? String(contentsOfFile: scriptPath, encoding: .utf8)
        else {
            print("❌ [BoostsManager] Failed to load darkreader.js")
            return []
        }
        
        // Normalize domain for comparison
        let normalizedDomain = normalizeDomain(domain)
        
        // Create font preloading script if needed (for custom fonts)
        let fontPreloadScript = getFontPreloadScript(for: config)
        
        // Create a script that loads DarkReader and applies boost config immediately
        // Fonts are handled via DarkReader's native API (useFont + fontFamily) for instant application
        let boostScript = getBoostApplyScript(for: config)
        let zoomScript = getZoomScript(for: config.pageZoom)
        let customCodeScript = getCustomCodeScript(for: config)
        
        // Unique identifier for boost scripts (used to identify and remove old scripts)
        let boostScriptIdentifier = "// NOOK_BOOST_SCRIPT_IDENTIFIER"
        
        // Single unified script - DarkReader handles fonts via fixes.css (optimized, instant)
        let combinedScript = """
            \(boostScriptIdentifier)
            (function() {
                // Domain check for boost features
                const currentDomain = window.location.hostname.toLowerCase().replace(/^www\\./, '');
                const targetDomain = '\(normalizedDomain)';
                
                // Extract top-level domain for comparison
                function getTopLevelDomain(hostname) {
                    const parts = hostname.split('.');
                    if (parts.length > 2) {
                        const lastTwo = parts.slice(-2).join('.');
                        const specialTLDs = ['co.uk', 'co.jp', 'com.au', 'co.nz', 'com.br'];
                        if (specialTLDs.includes(lastTwo) && parts.length > 3) {
                            return parts.slice(-3).join('.');
                        }
                        return lastTwo;
                    }
                    return hostname;
                }
                
                const currentTLD = getTopLevelDomain(currentDomain);
                const targetTLD = getTopLevelDomain(targetDomain);
                
                if (currentTLD !== targetTLD) {
                    return;
                }
                
                // Preload custom fonts if needed (async, won't block)
                \(fontPreloadScript)
                
                // Load DarkReader
                if (typeof DarkReader === 'undefined') {
                    \(darkreaderSource)
                }
                
                // Apply boost configuration (includes fonts via DarkReader's native API)
                // DarkReader uses theme.useFont and theme.fontFamily - instant application at document start
                if (typeof DarkReader !== 'undefined') {
                    \(boostScript)
                }
                
                // Apply other settings (zoom, custom code)
                \(zoomScript)
                \(customCodeScript)
            })();
            """
        
        // Single script - DarkReader handles everything including fonts via fixes.css
        let mainBoostScript = WKUserScript(
            source: combinedScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        let scripts: [WKUserScript] = [mainBoostScript]
        
        // Cache the array of scripts
        scriptCache[key] = scripts
        
        // Limit cache size to prevent memory issues
        if scriptCache.count > 50 {
            // Remove oldest entries (simple FIFO)
            let keysToRemove = Array(scriptCache.keys.prefix(scriptCache.count - 50))
            for key in keysToRemove {
                scriptCache.removeValue(forKey: key)
            }
        }
        
        print("✅ [BoostsManager] Created boost scripts for: \(domain) (\(scripts.count) scripts)")
        return scripts
    }
    
    /// Get JavaScript code for font preloading (for custom fonts)
    private func getFontPreloadScript(for config: BoostConfig) -> String {
        guard let fontFamily = config.fontFamily, !fontFamily.isEmpty else {
            return ""
        }
        
        // List of system fonts that don't need preloading
        let systemFonts = [
            "system", "San Francisco", "Helvetica Neue", "Helvetica", "Arial",
            "Times New Roman", "Courier", "Verdana", "Georgia", "Palatino",
            "Avenir", "Futura", "DIN Alternate", "Arial Rounded MT Bold",
            "PT Mono", "Courier New", "Times", "Charter", "Baskerville",
            "Hoefler Text", "Palatino", "Chalkboard", "SignPainter",
            "Snell Roundhand", "Papyrus", "Apple Chancery", "Wingdings"
        ]
        
        // Check if it's a system font
        if systemFonts.contains(where: { fontFamily.localizedCaseInsensitiveContains($0) }) {
            return "" // System fonts don't need preloading
        }
        
        // For custom fonts, try to preload using FontFace API
        // Note: This is best-effort and won't block if font isn't available
        return """
            (async function() {
                try {
                    // Check if FontFace API is available
                    if (typeof FontFace !== 'undefined') {
                        // Try to load the font (non-blocking)
                        const font = new FontFace('\(fontFamily)', `local('\(fontFamily)')`);
                        await font.load().catch(() => {
                            // Font not available locally, that's okay
                        });
                        if (font.status === 'loaded') {
                            document.fonts.add(font);
                        }
                    }
                } catch (e) {
                    // Font preloading failed, continue anyway
                }
            })();
        """
    }
    
    /// Inject DarkReader script into a webview with boost configuration
    func injectBoost(
        _ config: BoostConfig, into webView: WKWebView, completion: ((Bool) -> Void)? = nil
    ) {
        // First, inject the DarkReader library if not already present
        guard let scriptPath = Bundle.main.path(forResource: "darkreader", ofType: "js"),
            let darkreaderSource = try? String(contentsOfFile: scriptPath, encoding: .utf8)
        else {
            print("❌ [BoostsManager] Failed to load darkreader.js")
            completion?(false)
            return
        }

        // Check if DarkReader is already loaded
        let checkScript = "typeof DarkReader !== 'undefined'"
        webView.evaluateJavaScript(checkScript) { result, error in
            let isLoaded = (result as? Bool) ?? false

            if !isLoaded {
                // Inject DarkReader library first
                webView.evaluateJavaScript(darkreaderSource) { _, error in
                    if let error = error {
                        print("❌ [BoostsManager] Failed to inject DarkReader: \(error)")
                        completion?(false)
                        return
                    }

                    // Now apply the boost
                    self.applyBoostConfig(config, to: webView, completion: completion)
                    // Apply font settings, zoom, and custom code
                    self.applyFontSettings(config, to: webView)
                    self.applyPageZoom(config.pageZoom, to: webView)
                    self.applyCustomCode(config, to: webView)
                }
            } else {
                // DarkReader already loaded, just apply config
                self.applyBoostConfig(config, to: webView, completion: completion)
                // Apply font settings, zoom, and custom code
                self.applyFontSettings(config, to: webView)
                self.applyPageZoom(config.pageZoom, to: webView)
                self.applyCustomCode(config, to: webView)
            }
        }
    }

    /// Get JavaScript code to apply boost configuration
    /// Uses DarkReader's native font API (useFont + fontFamily) for instant font application
    func getBoostApplyScript(for config: BoostConfig) -> String {
        // Convert percentages to 0-1 range for DarkReader
        let brightness = config.brightness
        let contrast = config.contrast
        let sepia = config.sepia
        let tintStrength = config.tintStrength
        
        // Build theme object with DarkReader's native font API
        // DarkReader has built-in support for fonts via theme.useFont and theme.fontFamily
        // This is MORE optimized than fixes.css - it's part of DarkReader's core system!
        var themeOptions: [String] = [
            "brightness: \(brightness)",
            "contrast: \(contrast)",
            "sepia: \(sepia)",
            "mode: \(config.mode)",
            "tintColor: '\(config.tintColor)'",
            "tintStrength: \(tintStrength)"
        ]
        
        // Add font properties if font is configured
        // DarkReader's native API: useFont (boolean) and fontFamily (string)
        if let fontFamily = config.fontFamily, !fontFamily.isEmpty {
            let escapedFont = fontFamily
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            themeOptions.append("useFont: true")
            themeOptions.append("fontFamily: '\(escapedFont)'")
        }
        
        // Build fixes object for text-transform (DarkReader doesn't have native support for this)
        let fixesObject: String
        if config.textTransform != "none" {
            let escapedCSS = "html, body, input, textarea, button, select, [contenteditable] { text-transform: \(config.textTransform) !important; }"
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            
            fixesObject = "{ css: '\(escapedCSS)' }"
        } else {
            fixesObject = "null"
        }

        let themeObject = "{ \(themeOptions.joined(separator: ", ")) }"
        
        return """
            (function() {
                if (typeof DarkReader !== 'undefined') {
                    DarkReader.disable();
                    DarkReader.enable(\(themeObject), \(fixesObject));
                    console.log('✅ [Nook Boost] Applied boost with DarkReader native font API:', {brightness: \(brightness), contrast: \(contrast), sepia: \(sepia), tintColor: '\(config.tintColor)', tintStrength: \(tintStrength), useFont: \(config.fontFamily != nil && !config.fontFamily!.isEmpty), fontFamily: '\(config.fontFamily ?? "none")'});
                } else {
                    console.error('❌ [Nook Boost] DarkReader not loaded');
                }
            })();
            """
    }
    
    /// Get immediate font injection (sets font on html element directly, synchronous)
    private func getImmediateFontInjection(for config: BoostConfig) -> String {
        var injections: [String] = []
        
        if let fontFamily = config.fontFamily, !fontFamily.isEmpty {
            let escapedFont = fontFamily.replacingOccurrences(of: "'", with: "\\'")
            injections.append("document.documentElement.style.setProperty('font-family', '\(escapedFont)', 'important');")
        }
        
        if config.textTransform != "none" {
            injections.append("document.documentElement.style.setProperty('text-transform', '\(config.textTransform)', 'important');")
        }
        
        return injections.joined(separator: "\n                            ")
    }
    
    /// Get immediate style tag injection (minimal, fast CSS injection)
    private func getImmediateStyleInjection(for config: BoostConfig) -> String {
        var cssRules: [String] = []
        
        if let fontFamily = config.fontFamily, !fontFamily.isEmpty {
            let escapedFont = fontFamily.replacingOccurrences(of: "'", with: "\\'")
            
            // For system fonts, skip @font-face entirely - they're already available
            // System fonts don't need @font-face declarations, which saves parsing time
            // Just use the font name directly - browser will resolve it instantly
            if isSystemFont(fontFamily) {
                // System fonts are already loaded - use directly without @font-face
                // This is faster because:
                // 1. No @font-face parsing overhead
                // 2. No font resolution delay
                // 3. Browser uses cached system font immediately
                cssRules.append("font-family: '\(escapedFont)', sans-serif !important;")
            } else {
                // Custom fonts might need @font-face, but we handle that in preload script
                cssRules.append("font-family: '\(escapedFont)', sans-serif !important; font-synthesis: none;")
            }
        }
        
        if config.textTransform != "none" {
            cssRules.append("text-transform: \(config.textTransform) !important;")
        }
        
        guard !cssRules.isEmpty else { return "" }
        
        let css = cssRules.joined(separator: " ")
        
        // Inject with performance optimizations:
        // For system fonts, skip @font-face entirely (they're already available)
        // This reduces CSS parsing time and makes injection faster
        return """
                            const style = document.createElement('style');
                            style.id = 'nook-boost-font-immediate';
                            // Optimize for large DOMs: set font on html, let it inherit
                            // System fonts don't need @font-face - they're already loaded
                            style.textContent = 'html { \(css) } body { \(css) }';
                            // Insert at start of head for maximum priority
                            if (document.head.firstChild) {
                                document.head.insertBefore(style, document.head.firstChild);
                            } else {
                                document.head.appendChild(style);
                            }
        """
    }
    
    /// Check if a font is a system font (doesn't need network loading)
    private func isSystemFont(_ fontName: String) -> Bool {
        let systemFonts = [
            "system", "San Francisco", "Helvetica Neue", "Helvetica", "Arial",
            "Times New Roman", "Courier", "Verdana", "Georgia", "Palatino",
            "Avenir", "Futura", "DIN Alternate", "Arial Rounded MT Bold",
            "PT Mono", "Courier New", "Times", "Charter", "Baskerville",
            "Hoefler Text", "Palatino", "Chalkboard", "SignPainter",
            "Snell Roundhand", "Papyrus", "Apple Chancery", "Wingdings"
        ]
        return systemFonts.contains(where: { fontName.localizedCaseInsensitiveContains($0) })
    }
    
    /// Get JavaScript code for font settings (optimized with CSS variables and root scoping)
    /// This is the full implementation that runs after immediate injection
    private func getFontSettingsScript(for config: BoostConfig) -> String {
        var variableScripts: [String] = []
        var cssRules: [String] = []
        
        // Set CSS variables on root element for efficient updates
        if let fontFamily = config.fontFamily, !fontFamily.isEmpty {
            // Escape font name for CSS
            let escapedFont = fontFamily.replacingOccurrences(of: "'", with: "\\'")
            variableScripts.append("""
                document.documentElement.style.setProperty('--nook-boost-font-family', '\(escapedFont)', 'important');
            """)
            cssRules.append("font-family: var(--nook-boost-font-family, inherit) !important;")
        }
        
        if config.textTransform != "none" {
            variableScripts.append("""
                document.documentElement.style.setProperty('--nook-boost-text-transform', '\(config.textTransform)', 'important');
            """)
            cssRules.append("text-transform: var(--nook-boost-text-transform, inherit) !important;")
        }
        
        guard !cssRules.isEmpty else { return "" }
        
        let css = cssRules.joined(separator: "\n    ")
        
        return """
            (function() {
                // Set CSS variables first
                \(variableScripts.joined(separator: "\n                "))
                
                // Apply styles only to root elements (not every node) for performance
                const style = document.createElement('style');
                style.id = 'nook-boost-font-settings';
                style.textContent = 'html, body, input, textarea, button, select, [contenteditable] { \(css) }';
                document.head.appendChild(style);
            })();
            """
    }
    
    /// Get JavaScript code for page zoom
    private func getZoomScript(for zoom: Int) -> String {
        guard zoom != 100 else { return "" }
        let zoomValue = Double(zoom) / 100.0
        return """
            (function() {
                const style = document.createElement('style');
                style.id = 'nook-boost-page-zoom';
                style.textContent = 'html { zoom: \(zoomValue) !important; }';
                document.head.appendChild(style);
            })();
            """
    }
    
    /// Get JavaScript code for custom CSS/JS
    private func getCustomCodeScript(for config: BoostConfig) -> String {
        var scripts: [String] = []
        
        if !config.customCSS.isEmpty {
            let escapedCSS = config.customCSS
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            
            scripts.append("""
                (function() {
                    const style = document.createElement('style');
                    style.id = 'nook-boost-custom-css';
                    style.textContent = '\(escapedCSS)';
                    document.head.appendChild(style);
                })();
                """)
        }
        
        if !config.customJS.isEmpty {
            scripts.append(config.customJS)
        }
        
        return scripts.joined(separator: "\n")
    }

    /// Disable DarkReader on a webview
    func disableBoost(in webView: WKWebView, completion: ((Bool) -> Void)? = nil) {
        let disableScript = """
            (function() {
                if (typeof DarkReader !== 'undefined') {
                    DarkReader.disable();
                    console.log('✅ [Nook Boost] DarkReader disabled');
                }
            })();
            """

        webView.evaluateJavaScript(disableScript) { _, error in
            if let error = error {
                print("❌ [BoostsManager] Failed to disable DarkReader: \(error)")
                completion?(false)
            } else {
                print("✅ [BoostsManager] DarkReader disabled successfully")
                completion?(true)
            }
        }
    }
    
    /// Inject CSS into a webview
    func injectCSS(_ css: String, into webView: WKWebView) {
        let script: String
        
        if css.isEmpty {
            // Remove existing boost CSS if present
            script = """
                (function() {
                    const existingStyle = document.getElementById('nook-boost-custom-css');
                    if (existingStyle) {
                        existingStyle.remove();
                        console.log('✅ [Nook Boost] Custom CSS removed');
                    }
                })();
                """
        } else {
            // Escape CSS string for JavaScript (escape backslashes, quotes, newlines)
            let escapedCSS = css
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            
            script = """
                (function() {
                    // Remove existing boost CSS if present
                    const existingStyle = document.getElementById('nook-boost-custom-css');
                    if (existingStyle) {
                        existingStyle.remove();
                    }
                    
                    // Inject new CSS
                    const style = document.createElement('style');
                    style.id = 'nook-boost-custom-css';
                    style.textContent = '\(escapedCSS)';
                    document.head.appendChild(style);
                    console.log('✅ [Nook Boost] Custom CSS injected');
                })();
                """
        }
        
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ [BoostsManager] Failed to inject CSS: \(error)")
            } else {
                print("✅ [BoostsManager] CSS \(css.isEmpty ? "removed" : "injected") successfully")
            }
        }
    }
    
    /// Inject JavaScript into a webview
    func injectJavaScript(_ js: String, into webView: WKWebView, completion: ((Bool) -> Void)? = nil) {
        guard !js.isEmpty else {
            completion?(true)
            return
        }
        
        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                print("❌ [BoostsManager] Failed to inject JavaScript: \(error)")
                completion?(false)
            } else {
                print("✅ [BoostsManager] JavaScript injected successfully")
                completion?(true)
            }
        }
    }
    
    /// Apply font settings (font-family and text-transform) to a webview
    func applyFontSettings(_ config: BoostConfig, to webView: WKWebView) {
        var cssRules: [String] = []
        
        if let fontFamily = config.fontFamily, !fontFamily.isEmpty {
            cssRules.append("font-family: '\(fontFamily)', sans-serif !important;")
        }
        
        if config.textTransform != "none" {
            cssRules.append("text-transform: \(config.textTransform) !important;")
        }
        
        guard !cssRules.isEmpty else { return }
        
        let css = """
            * {
                \(cssRules.joined(separator: "\n    "))
            }
            """
        
        injectCSS(css, into: webView)
    }
    
    /// Apply page zoom using CSS zoom property (same as Cmd+/Cmd-)
    func applyPageZoom(_ zoom: Int, to webView: WKWebView) {
        // Convert percentage to zoom value (100% = 1.0, 90% = 0.9, etc.)
        let zoomValue = Double(zoom) / 100.0
        
        let script = """
            (function() {
                // Remove existing zoom style if present
                const existingStyle = document.getElementById('nook-boost-page-zoom');
                if (existingStyle) {
                    existingStyle.remove();
                }
                
                // Apply zoom to html element (affects entire page)
                const style = document.createElement('style');
                style.id = 'nook-boost-page-zoom';
                style.textContent = 'html { zoom: \(zoomValue) !important; }';
                document.head.appendChild(style);
                console.log('✅ [Nook Boost] Page zoom set to \(zoom)%');
            })();
            """
        
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ [BoostsManager] Failed to apply page zoom: \(error)")
            } else {
                print("✅ [BoostsManager] Page zoom set to \(zoom)%")
            }
        }
    }
    
    /// Apply custom CSS and JavaScript from config
    func applyCustomCode(_ config: BoostConfig, to webView: WKWebView) {
        if !config.customCSS.isEmpty {
            injectCSS(config.customCSS, into: webView)
        }
        
        if !config.customJS.isEmpty {
            injectJavaScript(config.customJS, into: webView) { success in
                if success {
                    print("✅ [BoostsManager] Custom JavaScript applied")
                }
            }
        }
    }

    // MARK: - Private Methods

    private func applyBoostConfig(
        _ config: BoostConfig, to webView: WKWebView, completion: ((Bool) -> Void)?
    ) {
        let applyScript = getBoostApplyScript(for: config)

        webView.evaluateJavaScript(applyScript) { _, error in
            if let error = error {
                print("❌ [BoostsManager] Failed to apply boost: \(error)")
                completion?(false)
            } else {
                print("✅ [BoostsManager] Boost applied successfully")
                completion?(true)
            }
        }
    }

    /// Normalize domain to top-level domain (e.g., "www.github.com" -> "github.com")
    private func normalizeDomain(_ domain: String) -> String {
        var normalized = domain.lowercased()

        // Remove www. prefix
        if normalized.hasPrefix("www.") {
            normalized = String(normalized.dropFirst(4))
        }

        // Extract top-level domain (handle subdomains)
        let components = normalized.components(separatedBy: ".")
        if components.count > 2 {
            // For domains like "subdomain.example.com", extract "example.com"
            // But preserve certain TLDs like "co.uk"
            let commonTLDs = ["co.uk", "co.jp", "com.au", "co.nz", "com.br"]
            let lastTwo = components.suffix(2).joined(separator: ".")

            if commonTLDs.contains(lastTwo) && components.count > 3 {
                // Return last 3 parts for these special TLDs
                return components.suffix(3).joined(separator: ".")
            } else {
                // Return last 2 parts for standard domains
                return lastTwo
            }
        }

        return normalized
    }

    private func loadBoosts() {
        guard let data = userDefaults.data(forKey: boostsKey) else { return }

        do {
            let decoder = JSONDecoder()
            boosts = try decoder.decode([String: BoostConfig].self, from: data)
            print("✅ [BoostsManager] Loaded \(boosts.count) boosts")
        } catch {
            print("❌ [BoostsManager] Failed to decode boosts: \(error)")
        }
    }

    private func persistBoosts() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(boosts)
            userDefaults.set(data, forKey: boostsKey)
            print("✅ [BoostsManager] Persisted \(boosts.count) boosts")
        } catch {
            print("❌ [BoostsManager] Failed to encode boosts: \(error)")
        }
    }
}
