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
    
    /// Create WKUserScript(s) for boost injection at document start
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
        
        let normalizedDomain = normalizeDomain(domain)
        let fontPreloadScript = getFontPreloadScript(for: config)
        let boostScript = getBoostApplyScript(for: config)
        let zoomScript = getZoomScript(for: config.pageZoom)
        let customCodeScript = getCustomCodeScript(for: config)
        let boostScriptIdentifier = "// NOOK_BOOST_SCRIPT_IDENTIFIER"
        
        let combinedScript = """
            \(boostScriptIdentifier)
            (function() {
                const currentDomain = window.location.hostname.toLowerCase().replace(/^www\\./, '');
                const targetDomain = '\(normalizedDomain)';
                
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
                
                \(fontPreloadScript)
                
                if (typeof DarkReader === 'undefined') {
                    \(darkreaderSource)
                }
                
                if (typeof DarkReader !== 'undefined') {
                    \(boostScript)
                }
                
                \(zoomScript)
                \(customCodeScript)
            })();
            """
        
        let mainBoostScript = WKUserScript(
            source: combinedScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        let scripts: [WKUserScript] = [mainBoostScript]
        
        scriptCache[key] = scripts
        
        if scriptCache.count > 50 {
            let keysToRemove = Array(scriptCache.keys.prefix(scriptCache.count - 50))
            for key in keysToRemove {
                scriptCache.removeValue(forKey: key)
            }
        }
        
        print("✅ [BoostsManager] Created boost scripts for: \(domain) (\(scripts.count) scripts)")
        return scripts
    }
    
    private func getFontPreloadScript(for config: BoostConfig) -> String {
        guard let fontFamily = config.fontFamily, !fontFamily.isEmpty else {
            return ""
        }
        
        let systemFonts = [
            "system", "San Francisco", "Helvetica Neue", "Helvetica", "Arial",
            "Times New Roman", "Courier", "Verdana", "Georgia", "Palatino",
            "Avenir", "Futura", "DIN Alternate", "Arial Rounded MT Bold",
            "PT Mono", "Courier New", "Times", "Charter", "Baskerville",
            "Hoefler Text", "Palatino", "Chalkboard", "SignPainter",
            "Snell Roundhand", "Papyrus", "Apple Chancery", "Wingdings"
        ]
        
        if systemFonts.contains(where: { fontFamily.localizedCaseInsensitiveContains($0) }) {
            return ""
        }
        
        return """
            (async function() {
                try {
                    if (typeof FontFace !== 'undefined') {
                        const font = new FontFace('\(fontFamily)', `local('\(fontFamily)')`);
                        await font.load().catch(() => {});
                        if (font.status === 'loaded') {
                            document.fonts.add(font);
                        }
                    }
                } catch (e) {}
            })();
        """
    }
    
    func injectBoost(
        _ config: BoostConfig, into webView: WKWebView, completion: ((Bool) -> Void)? = nil
    ) {
        guard let scriptPath = Bundle.main.path(forResource: "darkreader", ofType: "js"),
            let darkreaderSource = try? String(contentsOfFile: scriptPath, encoding: .utf8)
        else {
            print("❌ [BoostsManager] Failed to load darkreader.js")
            completion?(false)
            return
        }

        let checkScript = "typeof DarkReader !== 'undefined'"
        webView.evaluateJavaScript(checkScript) { result, error in
            let isLoaded = (result as? Bool) ?? false

            if !isLoaded {
                webView.evaluateJavaScript(darkreaderSource) { _, error in
                    if let error = error {
                        print("❌ [BoostsManager] Failed to inject DarkReader: \(error)")
                        completion?(false)
                        return
                    }

                    self.applyBoostConfig(config, to: webView, completion: completion)
                    self.applyFontSettings(config, to: webView)
                    self.applyPageZoom(config.pageZoom, to: webView)
                    self.applyCustomCode(config, to: webView)
                }
            } else {
                self.applyBoostConfig(config, to: webView, completion: completion)
                self.applyFontSettings(config, to: webView)
                self.applyPageZoom(config.pageZoom, to: webView)
                self.applyCustomCode(config, to: webView)
            }
        }
    }

    func getBoostApplyScript(for config: BoostConfig) -> String {
        let brightness = config.brightness
        let contrast = config.contrast
        let sepia = config.sepia
        let tintStrength = config.tintStrength
        
        var themeOptions: [String] = [
            "brightness: \(brightness)",
            "contrast: \(contrast)",
            "sepia: \(sepia)",
            "mode: \(config.mode)",
            "tintColor: '\(config.tintColor)'",
            "tintStrength: \(tintStrength)"
        ]
        
        if let fontFamily = config.fontFamily, !fontFamily.isEmpty {
            let escapedFont = fontFamily
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            themeOptions.append("useFont: true")
            themeOptions.append("fontFamily: '\(escapedFont)'")
        }
        
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
    
    private func getImmediateStyleInjection(for config: BoostConfig) -> String {
        var cssRules: [String] = []
        
        if let fontFamily = config.fontFamily, !fontFamily.isEmpty {
            let escapedFont = fontFamily.replacingOccurrences(of: "'", with: "\\'")
            
            if isSystemFont(fontFamily) {
                cssRules.append("font-family: '\(escapedFont)', sans-serif !important;")
            } else {
                cssRules.append("font-family: '\(escapedFont)', sans-serif !important; font-synthesis: none;")
            }
        }
        
        if config.textTransform != "none" {
            cssRules.append("text-transform: \(config.textTransform) !important;")
        }
        
        guard !cssRules.isEmpty else { return "" }
        
        let css = cssRules.joined(separator: " ")
        
        return """
                            const style = document.createElement('style');
                            style.id = 'nook-boost-font-immediate';
                            style.textContent = 'html { \(css) } body { \(css) }';
                            if (document.head.firstChild) {
                                document.head.insertBefore(style, document.head.firstChild);
                            } else {
                                document.head.appendChild(style);
                            }
        """
    }
    
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
    
    private func getFontSettingsScript(for config: BoostConfig) -> String {
        var variableScripts: [String] = []
        var cssRules: [String] = []
        
        if let fontFamily = config.fontFamily, !fontFamily.isEmpty {
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
                \(variableScripts.joined(separator: "\n                "))
                
                const style = document.createElement('style');
                style.id = 'nook-boost-font-settings';
                style.textContent = 'html, body, input, textarea, button, select, [contenteditable] { \(css) }';
                document.head.appendChild(style);
            })();
            """
    }
    
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
    
    func injectCSS(_ css: String, into webView: WKWebView) {
        let script: String
        
        if css.isEmpty {
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
            let escapedCSS = css
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
            
            script = """
                (function() {
                    const existingStyle = document.getElementById('nook-boost-custom-css');
                    if (existingStyle) {
                        existingStyle.remove();
                    }
                    
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
    
    func applyPageZoom(_ zoom: Int, to webView: WKWebView) {
        let zoomValue = Double(zoom) / 100.0
        
        let script = """
            (function() {
                const existingStyle = document.getElementById('nook-boost-page-zoom');
                if (existingStyle) {
                    existingStyle.remove();
                }
                
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

    private func normalizeDomain(_ domain: String) -> String {
        var normalized = domain.lowercased()

        if normalized.hasPrefix("www.") {
            normalized = String(normalized.dropFirst(4))
        }

        let components = normalized.components(separatedBy: ".")
        if components.count > 2 {
            let commonTLDs = ["co.uk", "co.jp", "com.au", "co.nz", "com.br"]
            let lastTwo = components.suffix(2).joined(separator: ".")

            if commonTLDs.contains(lastTwo) && components.count > 3 {
                return components.suffix(3).joined(separator: ".")
            } else {
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
