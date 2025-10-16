//
//  TweakManager.swift
//  Nook
//
//  Core manager for user-defined website customizations (Tweaks).
//

import Foundation
import WebKit
import SwiftData
import AppKit
import SwiftUI

@MainActor
final class TweakManager: ObservableObject {
    static let shared = TweakManager()

    @Published var availableTweaks: [TweakEntity] = []
    @Published var appliedTweaks: [AppliedTweak] = []
    @Published var isEnabled: Bool = true
    @Published var currentURL: URL?

    private let context: ModelContext
    private var webExtensionController: WKWebExtensionController?
    private weak var browserManagerRef: BrowserManager?

    // Cache for applied tweak scripts to avoid regeneration
    private var scriptCache: [UUID: (css: String, js: String)] = [:]

    private init() {
        self.context = Persistence.shared.container.mainContext
        loadTweaks()
        setupSettingsObserver()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupSettingsObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func settingsChanged() {
        let newEnabled = UserDefaults.standard.bool(forKey: "settings.enableTweaks")
        if newEnabled != isEnabled {
            isEnabled = newEnabled
            if !newEnabled {
                Task {
                    await clearAllAppliedTweaks()
                }
            }
        }
    }

    func attach(browserManager: BrowserManager) {
        self.browserManagerRef = browserManager
    }

    // MARK: - Tweak Lifecycle Management

    func createTweak(
        name: String,
        urlPattern: String,
        profileId: UUID? = nil,
        description: String? = nil
    ) -> TweakEntity? {
        // Validate URL pattern first
        let validation = TweakSecurityValidator.shared.validateURLPattern(urlPattern)
        if !validation.isValid {
            print("🎨 [TweakManager] URL pattern validation failed: \(validation.errors.joined(separator: ", "))")
            return nil
        }

        // Log warnings
        for warning in validation.warnings {
            print("🎨 [TweakManager] URL pattern warning: \(warning)")
        }

        let tweak = TweakEntity(
            name: name,
            urlPattern: urlPattern,
            profileId: profileId,
            tweakDescription: description
        )

        context.insert(tweak)
        saveContext()
        loadTweaks()

        print("🎨 [TweakManager] Created tweak: \(name) for pattern: \(urlPattern)")
        return tweak
    }

    func updateTweak(_ tweak: TweakEntity) {
        tweak.markAsModified()
        saveContext()

        // Clear cached scripts for this tweak
        scriptCache.removeValue(forKey: tweak.id)

        // Reapply tweaks if we're on a matching page
        if let currentURL = currentURL, tweak.matches(url: currentURL) {
            Task {
                await applyTweaksForURL(currentURL)
            }
        }

        print("🎨 [TweakManager] Updated tweak: \(tweak.name)")
    }

    func deleteTweak(_ tweak: TweakEntity) {
        // Remove from applied tweaks if currently active
        appliedTweaks.removeAll { $0.id == tweak.id }

        // Clear cached scripts
        scriptCache.removeValue(forKey: tweak.id)

        // Delete from database
        context.delete(tweak)
        saveContext()
        loadTweaks()

        // Reapply remaining tweaks
        if let currentURL = currentURL {
            Task {
                await applyTweaksForURL(currentURL)
            }
        }

        print("🎨 [TweakManager] Deleted tweak: \(tweak.name)")
    }

    func toggleTweak(_ tweak: TweakEntity) {
        tweak.isEnabled.toggle()
        updateTweak(tweak)

        if let currentURL = currentURL, tweak.matches(url: currentURL) {
            if tweak.isEnabled {
                print("🎨 [TweakManager] Enabled tweak: \(tweak.name)")
            } else {
                print("🎨 [TweakManager] Disabled tweak: \(tweak.name)")
            }
        }
    }

    func duplicateTweak(_ tweak: TweakEntity) -> TweakEntity? {
        let newTweak = TweakEntity(
            name: "\(tweak.name) (Copy)",
            urlPattern: tweak.urlPattern,
            profileId: tweak.profileId,
            tweakDescription: tweak.tweakDescription
        )

        // Copy all rules
        if let rules = fetchRules(for: tweak) {
            for rule in rules {
                let newRule = TweakRuleEntity(
                    type: rule.type,
                    selector: rule.selector,
                    value: rule.value,
                    isEnabled: rule.isEnabled,
                    priority: rule.priority,
                    createdDate: Date()
                )
                newRule.tweak = newTweak
                context.insert(newRule)
            }
        }

        context.insert(newTweak)
        saveContext()
        loadTweaks()

        print("🎨 [TweakManager] Duplicated tweak: \(tweak.name)")
        return newTweak
    }

    // MARK: - Rule Management

    func addRule(to tweak: TweakEntity, rule: TweakRuleEntity) -> Bool {
        // Validate rule before adding
        if let selector = rule.selector, !selector.isEmpty {
            let validation = TweakSecurityValidator.shared.validateCSSSelector(selector)
            if !validation.isValid {
                print("🎨 [TweakManager] CSS selector validation failed: \(validation.errors.joined(separator: ", "))")
                return false
            }

            // Log warnings
            for warning in validation.warnings {
                print("🎨 [TweakManager] CSS selector warning: \(warning)")
            }
        }

        // Validate custom code
        if rule.type == .customCSS, let css = rule.getCustomCSS() {
            let validation = TweakSecurityValidator.shared.validateCSS(css)
            if !validation.isValid {
                print("🎨 [TweakManager] Custom CSS validation failed: \(validation.errors.joined(separator: ", "))")
                return false
            }
        }

        if rule.type == .customJavaScript, let js = rule.getCustomJavaScript() {
            let validation = TweakSecurityValidator.shared.validateJavaScript(js)
            if !validation.isValid {
                print("🎨 [TweakManager] Custom JavaScript validation failed: \(validation.errors.joined(separator: ", "))")
                return false
            }
        }

        rule.tweak = tweak
        context.insert(rule)
        tweak.markAsModified()
        saveContext()

        // Clear cache and reapply if needed
        scriptCache.removeValue(forKey: tweak.id)
        if let currentURL = currentURL, tweak.matches(url: currentURL) {
            Task {
                await applyTweaksForURL(currentURL)
            }
        }

        print("🎨 [TweakManager] Added rule to tweak \(tweak.name): \(rule.type.displayName)")
        return true
    }

    func updateRule(_ rule: TweakRuleEntity) {
        if let tweak = rule.tweak {
            tweak.markAsModified()
            scriptCache.removeValue(forKey: tweak.id)

            if let currentURL = currentURL, tweak.matches(url: currentURL) {
                Task {
                    await applyTweaksForURL(currentURL)
                }
            }
        }

        saveContext()
        print("🎨 [TweakManager] Updated rule: \(rule.type.displayName)")
    }

    func deleteRule(_ rule: TweakRuleEntity) {
        let tweakId = rule.tweak?.id
        context.delete(rule)

        if let tweakId = tweakId {
            scriptCache.removeValue(forKey: tweakId)

            // Reapply tweaks if needed
            if let currentURL = currentURL,
               let tweak = availableTweaks.first(where: { $0.id == tweakId }),
               tweak.matches(url: currentURL) {
                Task {
                    await applyTweaksForURL(currentURL)
                }
            }
        }

        saveContext()
        print("🎨 [TweakManager] Deleted rule: \(rule.type.displayName)")
    }

    func toggleRule(_ rule: TweakRuleEntity) {
        rule.isEnabled.toggle()
        updateRule(rule)
    }

    // MARK: - URL Matching and Application

    func applyTweaksForURL(_ url: URL, in webView: WKWebView? = nil, profileId: UUID? = nil) async {
        guard isEnabled else {
            await clearAllAppliedTweaks()
            return
        }

        currentURL = url
        let matchingTweaks = availableTweaks.filter { $0.matches(url: url) }

        let newAppliedTweaks = matchingTweaks.compactMap { tweak in
            let rules = fetchRules(for: tweak) ?? []
            return AppliedTweak(from: tweak, rules: rules)
        }

        // Update applied tweaks
        appliedTweaks = newAppliedTweaks

        // Generate and inject scripts
        if let webView = webView {
            await injectTweaksIntoWebView(webView, for: newAppliedTweaks)
        } else {
            await injectTweakScripts(for: newAppliedTweaks, url: url)
        }

        print("🎨 [TweakManager] Applied \(newAppliedTweaks.count) tweaks for URL: \(url.host ?? url.absoluteString)")
    }

    func clearAllAppliedTweaks() async {
        appliedTweaks.removeAll()

        // Remove all injected scripts from webviews
        if let bm = browserManagerRef {
            let allTabs = bm.tabManager.pinnedTabs + bm.tabManager.tabs
            for tab in allTabs {
                await clearTweaksFromWebView(tab.webView)
            }
        }

        print("🎨 [TweakManager] Cleared all applied tweaks")
    }

    // MARK: - Script Generation and Injection

    private func injectTweakScripts(for tweaks: [AppliedTweak], url: URL) async {
        guard let bm = browserManagerRef else { return }

        let allTabs = bm.tabManager.pinnedTabs + bm.tabManager.tabs
        for tab in allTabs {
            guard let webView = tab.webView,
                  let currentTabURL = webView.url,
                  currentTabURL.absoluteString == url.absoluteString else { continue }

            await injectTweaksIntoWebView(webView, for: tweaks)
        }
    }

    func injectTweaksIntoWebView(_ webView: WKWebView?, for tweaks: [AppliedTweak]) async {
        guard let webView = webView else { return }

        var combinedCSS = ""
        var combinedJS = ""

        // Generate CSS and JS for all applicable tweaks
        for tweak in tweaks {
            let (css, js) = await generateScripts(for: tweak)
            combinedCSS += css + "\n"
            combinedJS += js + "\n"
        }

        // Remove existing tweak scripts
        await clearTweaksFromWebView(webView)

        // Inject CSS
        if !combinedCSS.isEmpty {
            let cssScript = WKUserScript(
                source: createCSSInjectionScript(combinedCSS),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.addUserScript(cssScript)
        }

        // Inject JavaScript with MutationObserver for dynamic content
        if !combinedCSS.isEmpty || !combinedJS.isEmpty {
            let jsScript = WKUserScript(
                source: createJSInjectionScript(combinedCSS, combinedJS),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.addUserScript(jsScript)
        }
    }

    func clearTweaksFromWebView(_ webView: WKWebView?) async {
        guard let webView = webView else { return }

        // Remove existing tweak user scripts
        let existingScripts = webView.configuration.userContentController.userScripts
        let filteredScripts = existingScripts.filter { script in
            !(script.source.contains("nook-tweak-injection") ||
              script.source.contains("nook-tweak-css") ||
              script.source.contains("nook-tweak-js"))
        }

        // Rebuild user content controller with filtered scripts
        let newUserContentController = WKUserContentController()
        for script in filteredScripts {
            newUserContentController.addUserScript(script)
        }

        // Note: Preserving message handlers is not directly supported in this WebKit version
        // The recreation of userContentController may affect other features
        // This is a limitation of the current WebKit API

        webView.configuration.userContentController = newUserContentController

        // Remove existing DOM elements
        do {
            try await webView.evaluateJavaScript("""
                if (window.nookTweaks) {
                    window.nookTweaks.cleanup();
                    window.nookTweaks = null;
                }
            """)
        } catch {
            print("🎨 [TweakManager] Failed to cleanup tweaks in WebView: \(error)")
        }
    }

    private func generateScripts(for tweak: AppliedTweak) async -> (css: String, js: String) {
        // Check cache first
        if let cached = scriptCache[tweak.id] {
            return cached
        }

        var cssRules: [String] = []
        var jsCode: [String] = []

        // Sort rules by priority
        let sortedRules = tweak.rules.sorted { $0.priority > $1.priority }

        for rule in sortedRules {
            switch rule.type {
            case .colorAdjustment:
                if let css = generateColorAdjustmentCSS(rule) {
                    cssRules.append(css)
                }

            case .fontOverride:
                if let css = generateFontOverrideCSS(rule) {
                    cssRules.append(css)
                }

            case .sizeTransform:
                if let css = generateSizeTransformCSS(rule) {
                    cssRules.append(css)
                }

            case .caseTransform:
                if let css = generateCaseTransformCSS(rule) {
                    cssRules.append(css)
                }

            case .elementHide:
                if let css = generateElementHideCSS(rule) {
                    cssRules.append(css)
                }

            case .customCSS:
                if let css = rule.getCustomCSS() {
                    // Validate CSS before using it
                    let validation = TweakSecurityValidator.shared.validateCSS(css)
                    if validation.isValid {
                        cssRules.append("/* Custom CSS for \(tweak.name) */\n" + css)
                    } else {
                        print("🎨 [TweakManager] CSS validation failed for tweak \(tweak.name): \(validation.errors.joined(separator: ", "))")
                        // Add warning comments
                        cssRules.append("/* CSS validation failed - rule disabled */")
                    }

                    // Log warnings
                    for warning in validation.warnings {
                        print("🎨 [TweakManager] CSS warning for tweak \(tweak.name): \(warning)")
                    }
                }

            case .customJavaScript:
                if let js = rule.getCustomJavaScript() {
                    // Validate and sanitize JavaScript before using it
                    let validation = TweakSecurityValidator.shared.validateJavaScript(js)
                    if validation.isValid {
                        // Wrap user code in sandbox
                        let sandboxedJS = """
                        try {
                            // User code runs in sandboxed context
                            (function() {
                                with (window.nookTweaksSandbox || window.nookTweakBase.createSandbox()) {
                                    \(validation.sanitizedCode)
                                }
                            })();
                        } catch (error) {
                            console.error('[Nook Tweaks] User script error:', error);
                        }
                        """
                        jsCode.append("/* Custom JavaScript for \(tweak.name) */\n" + sandboxedJS)
                    } else {
                        print("🎨 [TweakManager] JavaScript validation failed for tweak \(tweak.name): \(validation.errors.joined(separator: ", "))")
                        // Add error comment
                        jsCode.append("/* JavaScript validation failed - rule disabled */")
                    }

                    // Log warnings
                    for warning in validation.warnings {
                        print("🎨 [TweakManager] JavaScript warning for tweak \(tweak.name): \(warning)")
                    }
                }
            }
        }

        let combinedCSS = cssRules.joined(separator: "\n")
        let combinedJS = jsCode.joined(separator: "\n")

        // Cache the result
        scriptCache[tweak.id] = (css: combinedCSS, js: combinedJS)

        return (css: combinedCSS, js: combinedJS)
    }

    // MARK: - CSS Generation Methods

    private func generateColorAdjustmentCSS(_ rule: AppliedTweakRule) -> String? {
        guard let adjustment = rule.getColorAdjustment() else { return nil }

        let target = rule.selector ?? "body"
        let filterValue: String

        switch adjustment.type {
        case .hueRotate:
            filterValue = "hue-rotate(\(adjustment.amount)deg)"
        case .brightness:
            filterValue = "brightness(\(adjustment.amount))"
        case .contrast:
            filterValue = "contrast(\(adjustment.amount))"
        case .saturation:
            filterValue = "saturate(\(adjustment.amount))"
        case .invert:
            filterValue = "invert(\(adjustment.amount))"
        }

        return """
        /* Color Adjustment: \(adjustment.type.displayName) */
        \(target) {
            filter: \(filterValue) !important;
        }
        """
    }

    private func generateFontOverrideCSS(_ rule: AppliedTweakRule) -> String? {
        guard let font = rule.getFontOverride() else { return nil }

        let target = rule.selector ?? "body"
        let weight = font.weight
        let fallback = font.fallback

        return """
        /* Font Override: \(font.fontFamily) */
        \(target) {
            font-family: "\(font.fontFamily)", \(fallback) !important;
            font-weight: \(weight) !important;
        }
        """
    }

    private func generateSizeTransformCSS(_ rule: AppliedTweakRule) -> String? {
        guard let transform = rule.getSizeTransform() else { return nil }

        let target = rule.selector ?? "body"
        let transformValue = "scale(\(transform.scale))"

        return """
        /* Size Transform: scale(\(transform.scale)) */
        \(target) {
            transform: \(transformValue) !important;
            transform-origin: top left !important;
        }
        """
    }

    private func generateCaseTransformCSS(_ rule: AppliedTweakRule) -> String? {
        guard let caseType = rule.getCaseTransform() else { return nil }

        let target = rule.selector ?? "body"
        let textTransform: String

        switch caseType {
        case .uppercase:
            textTransform = "uppercase"
        case .lowercase:
            textTransform = "lowercase"
        case .capitalize:
            textTransform = "capitalize"
        }

        return """
        /* Case Transform: \(caseType.displayName) */
        \(target) {
            text-transform: \(textTransform) !important;
        }
        """
    }

    private func generateElementHideCSS(_ rule: AppliedTweakRule) -> String? {
        guard let selector = rule.getElementHideSelector() else { return nil }

        return """
        /* Element Hide: \(selector) */
        \(selector) {
            display: none !important;
        }
        """
    }

    // MARK: - JavaScript Generation

    private func createCSSInjectionScript(_ css: String) -> String {
        return """
        /* Nook Tweaks CSS Injection */
        (function() {
            if (typeof window.nookTweaks === 'undefined') {
                window.nookTweaks = {
                    cleanup: function() {
                        const style = document.getElementById('nook-tweak-styles');
                        if (style) style.remove();
                    }
                };
            }

            const style = document.createElement('style');
            style.id = 'nook-tweak-styles';
            style.textContent = `\(css.replacingOccurrences(of: "`", with: "\\`").replacingOccurrences(of: "${", with: "\\${"))}`;
            document.head.appendChild(style);
        })();
        """
    }

    private func createJSInjectionScript(_ css: String, _ js: String) -> String {
        return """
        /* Nook Tweaks JavaScript Injection */
        (function() {
            if (typeof window.nookTweaks === 'undefined') {
                window.nookTweaks = {
                    observer: null,
                    originalStyles: new Map(),
                    cleanup: function() {
                        if (this.observer) {
                            this.observer.disconnect();
                            this.observer = null;
                        }
                        // Restore original styles
                        this.originalStyles.forEach((style, element) => {
                            element.style.cssText = style;
                        });
                        this.originalStyles.clear();
                    }
                };
            }

            // Store current styles before modifications
            document.querySelectorAll('*').forEach(el => {
                window.nookTweaks.originalStyles.set(el, el.style.cssText);
            });

            // Reapply CSS rules when DOM changes
            function reapplyTweaks() {
                const style = document.getElementById('nook-tweak-styles');
                if (style) {
                    // Style already exists, just ensure it's still in head
                    if (!document.head.contains(style)) {
                        document.head.appendChild(style);
                    }
                }
            }

            // Create MutationObserver for dynamic content
            if (window.nookTweaks.observer) {
                window.nookTweaks.observer.disconnect();
            }

            window.nookTweaks.observer = new MutationObserver(function(mutations) {
                let shouldReapply = false;
                mutations.forEach(function(mutation) {
                    if (mutation.type === 'childList' && mutation.addedNodes.length > 0) {
                        shouldReapply = true;
                    }
                });
                if (shouldReapply) {
                    reapplyTweaks();
                }
            });

            window.nookTweaks.observer.observe(document.body, {
                childList: true,
                subtree: true
            });

            // Execute custom JavaScript
            try {
                \(js)
            } catch (error) {
                console.error('Nook Tweaks JavaScript error:', error);
            }
        })();
        """
    }

    // MARK: - Data Management

    private func loadTweaks() {
        do {
            availableTweaks = try context.fetch(FetchDescriptor<TweakEntity>())
                .sorted { $0.createdDate > $1.createdDate }
            print("🎨 [TweakManager] Loaded \(availableTweaks.count) tweaks")
        } catch {
            print("🎨 [TweakManager] Failed to load tweaks: \(error)")
            availableTweaks = []
        }
    }

    private func fetchRules(for tweak: TweakEntity) -> [TweakRuleEntity]? {
        do {
            // Fetch all rules and filter in memory - simpler and more reliable
            let allRules = try context.fetch(FetchDescriptor<TweakRuleEntity>())
            let rules = allRules
                .filter { $0.tweak?.id == tweak.id && $0.isEnabled }
                .sorted { $0.priority > $1.priority }
            return rules
        } catch {
            print("🎨 [TweakManager] Failed to fetch rules for tweak \(tweak.name): \(error)")
            return []
        }
    }

    private func saveContext() {
        do {
            try context.save()
        } catch {
            print("🎨 [TweakManager] Failed to save context: \(error)")
        }
    }

    // MARK: - Public Query Methods

    func getTweaksForURL(_ url: URL) -> [TweakEntity] {
        return availableTweaks.filter { $0.matches(url: url) }
    }

    func getTweak(id: UUID) -> TweakEntity? {
        return availableTweaks.first { $0.id == id }
    }

    func getRules(for tweak: TweakEntity) -> [TweakRuleEntity] {
        return fetchRules(for: tweak) ?? []
    }

    func exportTweaks() -> [[String: Any]] {
        return availableTweaks.map { tweak in
            var tweakDict: [String: Any] = [
                "name": tweak.name,
                "urlPattern": tweak.urlPattern,
                "isEnabled": tweak.isEnabled,
                "createdDate": tweak.createdDate.iso8601String,
                "description": tweak.tweakDescription as Any,
                "version": tweak.version
            ]

            let rules = getRules(for: tweak)
            tweakDict["rules"] = rules.map { rule in
                var ruleDict: [String: Any] = [
                    "type": rule.type.rawValue,
                    "selector": rule.selector as Any,
                    "value": rule.value as Any,
                    "isEnabled": rule.isEnabled,
                    "priority": rule.priority,
                    "createdDate": rule.createdDate.iso8601String
                ]
                return ruleDict
            }

            return tweakDict
        }
    }

    func importTweaks(from data: [[String: Any]]) -> Int {
        var importedCount = 0

        for tweakDict in data {
            guard let name = tweakDict["name"] as? String,
                  let urlPattern = tweakDict["urlPattern"] as? String else { continue }

            // Check if tweak with same name and pattern already exists
            if availableTweaks.contains(where: { $0.name == name && $0.urlPattern == urlPattern }) {
                continue
            }

            guard let tweak = createTweak(
                name: name,
                urlPattern: urlPattern,
                description: tweakDict["description"] as? String
            ) else { continue }

            if let rulesData = tweakDict["rules"] as? [[String: Any]] {
                for ruleDict in rulesData {
                    guard let typeString = ruleDict["type"] as? String,
                          let type = TweakRuleType(rawValue: typeString) else { continue }

                    let rule = TweakRuleEntity(
                        type: type,
                        selector: ruleDict["selector"] as? String,
                        value: ruleDict["value"] as? String,
                        isEnabled: ruleDict["isEnabled"] as? Bool ?? true,
                        priority: ruleDict["priority"] as? Int ?? 0,
                        createdDate: Date()
                    )

                    addRule(to: tweak, rule: rule)
                }
            }

            importedCount += 1
        }

        print("🎨 [TweakManager] Imported \(importedCount) tweaks")
        return importedCount
    }
}

// MARK: - Date Extension
extension Date {
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}

// MARK: - Error Types
enum TweakError: LocalizedError {
    case invalidURLPattern(String)
    case invalidSelector(String)
    case scriptGenerationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURLPattern(let pattern):
            return "Invalid URL pattern: \(pattern)"
        case .invalidSelector(let selector):
            return "Invalid CSS selector: \(selector)"
        case .scriptGenerationFailed(let reason):
            return "Failed to generate tweak scripts: \(reason)"
        }
    }
}