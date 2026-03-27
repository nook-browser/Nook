//
//  AdvancedBlockingEngine.swift
//  Nook
//
//  Replaces ScriptletEngine + FilterListParser for advanced blocking rules.
//  Uses AdGuard's Scriptlets corelibs JSON to generate executable JavaScript
//  from advancedRulesText produced by SafariConverterLib.
//

import Foundation
import WebKit
import OSLog

private let abLog = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "AdvancedBlocking")

// MARK: - Parsed Rule Types

/// A scriptlet rule parsed from advancedRulesText.
private struct ParsedScriptletRule {
    let name: String
    let args: [String]
    let permittedDomains: [String]
    let restrictedDomains: [String]
    let isException: Bool
}

/// A CSS injection rule parsed from advancedRulesText.
private struct ParsedCSSRule {
    let css: String
    let permittedDomains: [String]
    let restrictedDomains: [String]
    let isException: Bool
}

/// A cosmetic/extended CSS rule parsed from advancedRulesText.
private struct ParsedCosmeticRule {
    let selector: String
    let permittedDomains: [String]
    let restrictedDomains: [String]
    let isException: Bool
    let isExtendedCSS: Bool
}

// MARK: - AdGuard Scriptlet Library

/// Represents a single scriptlet from the AdGuard corelibs JSON.
private struct AdGuardScriptlet {
    let names: [String]
    let functionBody: String
}

// MARK: - AdvancedBlockingEngine

@MainActor
final class AdvancedBlockingEngine {

    private var scriptletRules: [ParsedScriptletRule] = []
    private var cssRules: [ParsedCSSRule] = []
    private var cosmeticRules: [ParsedCosmeticRule] = []

    /// Scriptlet name → executable function source code
    private var scriptletLibrary: [String: String] = [:]

    /// Cache of generated JS by domain (domain → concatenated JS string)
    private var scriptletCache: [String: String] = [:]
    private var cssCache: [String: String] = [:]

    /// Site-specific blocker scripts loaded from bundle (domain → JS source)
    private var siteSpecificScripts: [String: String] = [:]

    init() {
        loadScriptletLibrary()
        loadSiteSpecificScripts()
    }

    // MARK: - Configuration

    /// Configure the engine with advancedRulesText from SafariConverterLib.
    /// These are the rules that need JS-based injection (scriptlets, CSS inject, extended CSS).
    /// SafariConverterLib has already filtered out network rules and simple cosmetic rules.
    func configure(advancedRulesText: String?) {
        scriptletRules.removeAll()
        cssRules.removeAll()
        cosmeticRules.removeAll()
        scriptletCache.removeAll()
        cssCache.removeAll()

        guard let text = advancedRulesText, !text.isEmpty else {
            abLog.info("No advanced rules to configure")
            return
        }

        let lines = text.components(separatedBy: "\n")
        var scriptletCount = 0
        var cssCount = 0
        var cosmeticCount = 0

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("!") { continue }

            if let rule = parseScriptletRule(trimmed) {
                scriptletRules.append(rule)
                scriptletCount += 1
            } else if let rule = parseCSSInjectionRule(trimmed) {
                cssRules.append(rule)
                cssCount += 1
            } else if let rule = parseCosmeticRule(trimmed) {
                cosmeticRules.append(rule)
                cosmeticCount += 1
            }
        }

        abLog.info("Advanced blocking configured: \(scriptletCount) scriptlets, \(cssCount) CSS inject, \(cosmeticCount) cosmetic (from \(lines.count) advanced rules)")
    }

    // MARK: - Per-Navigation Injection

    /// Generate WKUserScripts for a given URL.
    /// Returns scripts for scriptlet injection, CSS injection, and cosmetic hiding.
    func userScripts(for url: URL) -> [WKUserScript] {
        guard let host = url.host?.lowercased() else { return [] }

        var scripts: [WKUserScript] = []

        // Scriptlet injection
        let scriptletJS = generateScriptletJS(for: host)
        if !scriptletJS.isEmpty {
            let markedJS = "// Nook Content Blocker\n" + scriptletJS
            scripts.append(WKUserScript(
                source: markedJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        // Generic scriptlets (no domain restriction — apply to all frames for iframe ads)
        let genericScriptletJS = generateGenericScriptletJS()
        if !genericScriptletJS.isEmpty {
            let markedJS = "// Nook Content Blocker\n" + genericScriptletJS
            scripts.append(WKUserScript(
                source: markedJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }

        // CSS injection rules
        let cssJS = generateCSSInjectionJS(for: host)
        if !cssJS.isEmpty {
            let markedJS = "// Nook Content Blocker\n" + cssJS
            scripts.append(WKUserScript(
                source: markedJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        // Extended CSS / cosmetic rules
        let cosmeticJS = generateCosmeticJS(for: host)
        if !cosmeticJS.isEmpty {
            let markedJS = "// Nook Content Blocker\n" + cosmeticJS
            scripts.append(WKUserScript(
                source: markedJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
        }

        // Site-specific blocker scripts (e.g., Facebook sponsored post detection)
        if let siteJS = siteSpecificScript(for: host) {
            let markedJS = "// Nook Content Blocker\n" + siteJS
            scripts.append(WKUserScript(
                source: markedJS,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            ))
            abLog.info("Injecting site-specific script for \(host, privacy: .public)")
        }

        abLog.info("userScripts for \(host, privacy: .public): \(scripts.count) total (scriptlet=\(!scriptletJS.isEmpty), generic=\(!genericScriptletJS.isEmpty), css=\(!cssJS.isEmpty), cosmetic=\(!cosmeticJS.isEmpty), site=\(self.siteSpecificScript(for: host) != nil))")

        return scripts
    }

    // MARK: - Scriptlet Library Loading

    private func loadScriptletLibrary() {
        guard let url = Bundle.main.url(forResource: "scriptlets.corelibs", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            abLog.error("Failed to load scriptlets.corelibs.json from bundle")
            return
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scriptletsArray = json["scriptlets"] as? [[String: Any]] else {
            abLog.error("Failed to parse scriptlets.corelibs.json")
            return
        }

        for entry in scriptletsArray {
            guard let names = entry["names"] as? [String],
                  let functionBody = entry["scriptlet"] as? String else { continue }

            for name in names {
                scriptletLibrary[name] = functionBody
            }
        }

        abLog.info("Loaded \(self.scriptletLibrary.count) scriptlet aliases from AdGuard corelibs")
    }

    /// Load site-specific blocker scripts from Resources/.
    private func loadSiteSpecificScripts() {
        let scripts: [(resource: String, domains: [String])] = [
            ("facebook-sponsored-blocker", ["facebook.com", "www.facebook.com", "m.facebook.com", "web.facebook.com"]),
            ("youtube-ad-blocker", ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "tv.youtube.com", "youtubekids.com", "youtube-nocookie.com"]),
        ]

        for entry in scripts {
            guard let path = Bundle.main.path(forResource: entry.resource, ofType: "js"),
                  let source = try? String(contentsOfFile: path, encoding: .utf8) else {
                abLog.warning("Failed to load site-specific script: \(entry.resource, privacy: .public)")
                continue
            }
            for domain in entry.domains {
                siteSpecificScripts[domain] = source
            }
        }

        abLog.info("Loaded \(self.siteSpecificScripts.count) site-specific script mappings")
    }

    /// Find a site-specific script for the given host.
    private func siteSpecificScript(for host: String) -> String? {
        if let script = siteSpecificScripts[host] { return script }
        let parts = host.split(separator: ".", maxSplits: 1)
        if parts.count == 2, let script = siteSpecificScripts[String(parts[1])] {
            return script
        }
        return nil
    }

    // MARK: - Rule Parsing

    /// Parse scriptlet rule in either format:
    /// - AdGuard:  `domain1,domain2#%#//scriptlet("name", "arg1", "arg2")`
    /// - uBlock:   `domain1,domain2##+js(scriptlet-name, arg1, arg2)`
    /// Exception forms: `#@%#//scriptlet(` or `#@#+js(`
    private func parseScriptletRule(_ line: String) -> ParsedScriptletRule? {
        let isException: Bool
        let separatorEnd: String.Index
        let isUBOFormat: Bool

        // Try all four separator patterns (exception variants first — they're longer)
        if let range = line.range(of: "#@%#//scriptlet(") {
            isException = true
            separatorEnd = range.upperBound
            isUBOFormat = false
        } else if let range = line.range(of: "#%#//scriptlet(") {
            isException = false
            separatorEnd = range.upperBound
            isUBOFormat = false
        } else if let range = line.range(of: "#@#+js(") {
            isException = true
            separatorEnd = range.upperBound
            isUBOFormat = true
        } else if let range = line.range(of: "##+js(") {
            isException = false
            separatorEnd = range.upperBound
            isUBOFormat = true
        } else {
            return nil
        }

        // Domain part is everything before the separator
        let separatorStart: String.Index
        if isException {
            if isUBOFormat {
                separatorStart = line.range(of: "#@#+js(")!.lowerBound
            } else {
                separatorStart = line.range(of: "#@%#//scriptlet(")!.lowerBound
            }
        } else {
            if isUBOFormat {
                separatorStart = line.range(of: "##+js(")!.lowerBound
            } else {
                separatorStart = line.range(of: "#%#//scriptlet(")!.lowerBound
            }
        }

        let domainPart = String(line[line.startIndex..<separatorStart])
        let (permitted, restricted) = parseDomains(domainPart)

        // Extract everything between the opening ( and the trailing )
        let afterOpen = String(line[separatorEnd...])
        guard afterOpen.hasSuffix(")") else { return nil }
        let argsString = String(afterOpen.dropLast())

        // Parse arguments
        let args: [String]
        let name: String
        let scriptletArgs: [String]

        if isUBOFormat {
            // uBlock format: ##+js(scriptlet-name, arg1, arg2)
            // Arguments are comma-separated, NOT quoted (but may have spaces)
            let parts = argsString.split(separator: ",", maxSplits: .max, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard !parts.isEmpty, !parts[0].isEmpty else { return nil }
            name = parts[0]
            scriptletArgs = Array(parts.dropFirst())
        } else {
            // AdGuard format: #%#//scriptlet("name", "arg1", "arg2")
            // Arguments are comma-separated and quoted
            args = parseQuotedArgs(argsString)
            guard !args.isEmpty else { return nil }
            name = args[0]
            scriptletArgs = Array(args.dropFirst())
        }

        return ParsedScriptletRule(
            name: name,
            args: scriptletArgs,
            permittedDomains: permitted,
            restrictedDomains: restricted,
            isException: isException
        )
    }

    /// Parse CSS injection rule: `domain#$#selector { style }` or `domain#$?#selector:ext { style }`
    /// Exception form: `domain#@$#selector { style }` or `domain#@$?#selector:ext { style }`
    private func parseCSSInjectionRule(_ line: String) -> ParsedCSSRule? {
        let isException: Bool
        let separatorRange: Range<String.Index>?

        // Try exception forms first (longer separator)
        if let range = line.range(of: "#@$?#") {
            isException = true
            separatorRange = range
        } else if let range = line.range(of: "#@$#") {
            isException = true
            separatorRange = range
        } else if let range = line.range(of: "#$?#") {
            isException = false
            separatorRange = range
        } else if let range = line.range(of: "#$#") {
            isException = false
            separatorRange = range
        } else {
            return nil
        }

        guard let sepRange = separatorRange else { return nil }

        // Make sure this isn't a scriptlet rule (which also contains #%# or #$#)
        let afterSep = String(line[sepRange.upperBound...])
        if afterSep.hasPrefix("//scriptlet(") { return nil }

        let domainPart = String(line[line.startIndex..<sepRange.lowerBound])
        let (permitted, restricted) = parseDomains(domainPart)

        let css = afterSep.trimmingCharacters(in: .whitespaces)
        guard !css.isEmpty else { return nil }

        return ParsedCSSRule(
            css: css,
            permittedDomains: permitted,
            restrictedDomains: restricted,
            isException: isException
        )
    }

    /// Parse cosmetic/extended CSS rule: `domain##selector` or `domain#?#selector`
    /// Exception form: `domain#@#selector` or `domain#@?#selector`
    private func parseCosmeticRule(_ line: String) -> ParsedCosmeticRule? {
        let isException: Bool
        let isExtended: Bool
        let separatorRange: Range<String.Index>?

        if let range = line.range(of: "#@?#") {
            isException = true
            isExtended = true
            separatorRange = range
        } else if let range = line.range(of: "#?#") {
            isException = false
            isExtended = true
            separatorRange = range
        } else if let range = line.range(of: "#@#") {
            isException = true
            isExtended = false
            separatorRange = range
        } else if let range = line.range(of: "##") {
            isException = false
            isExtended = false
            separatorRange = range
        } else {
            return nil
        }

        guard let sepRange = separatorRange else { return nil }

        let domainPart = String(line[line.startIndex..<sepRange.lowerBound])
        let (permitted, restricted) = parseDomains(domainPart)

        let selector = String(line[sepRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !selector.isEmpty else { return nil }

        // Detect extended CSS pseudo-classes even in ## rules
        let extIndicators = [":has-text(", ":contains(", ":matches-css(", ":xpath(",
                             ":nth-ancestor(", ":upward(", ":remove(", ":matches-attr(",
                             ":matches-property(", "[-ext-"]
        let actuallyExtended = isExtended || extIndicators.contains(where: { selector.contains($0) })

        return ParsedCosmeticRule(
            selector: selector,
            permittedDomains: permitted,
            restrictedDomains: restricted,
            isException: isException,
            isExtendedCSS: actuallyExtended
        )
    }

    // MARK: - Domain Matching

    private func parseDomains(_ domainString: String) -> (permitted: [String], restricted: [String]) {
        guard !domainString.isEmpty else { return ([], []) }

        var permitted: [String] = []
        var restricted: [String] = []

        let parts = domainString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        for part in parts {
            if part.hasPrefix("~") {
                restricted.append(String(part.dropFirst()))
            } else {
                permitted.append(part)
            }
        }

        return (permitted, restricted)
    }

    private func domainMatches(_ host: String, permitted: [String], restricted: [String]) -> Bool {
        // Check restricted domains first — if host matches any, rule doesn't apply
        for domain in restricted {
            if host == domain || host.hasSuffix("." + domain) {
                return false
            }
        }

        // If no permitted domains, rule applies everywhere (minus restricted)
        if permitted.isEmpty {
            return true
        }

        // Check if host matches any permitted domain
        for domain in permitted {
            if host == domain || host.hasSuffix("." + domain) {
                return true
            }
        }

        return false
    }

    // MARK: - JS Generation

    private func generateScriptletJS(for host: String) -> String {
        if let cached = scriptletCache[host] { return cached }

        // Collect exception scriptlet names for this domain
        var exceptionNames: Set<String> = []
        for rule in scriptletRules where rule.isException {
            if domainMatches(host, permitted: rule.permittedDomains, restricted: rule.restrictedDomains) {
                exceptionNames.insert(rule.name)
            }
        }

        var jsFragments: [String] = []

        for rule in scriptletRules {
            if rule.isException { continue }
            if rule.permittedDomains.isEmpty { continue } // Generic rules handled separately
            if exceptionNames.contains(rule.name) { continue }
            if !domainMatches(host, permitted: rule.permittedDomains, restricted: rule.restrictedDomains) { continue }

            if let js = buildScriptletInvocation(rule) {
                jsFragments.append(js)
            }
        }

        let result = jsFragments.joined(separator: "\n")
        scriptletCache[host] = result
        return result
    }

    private func generateGenericScriptletJS() -> String {
        // Generic scriptlets (no domain restriction) — these apply everywhere
        var jsFragments: [String] = []

        for rule in scriptletRules {
            if rule.isException { continue }
            if !rule.permittedDomains.isEmpty { continue } // Domain-specific handled elsewhere
            if !rule.restrictedDomains.isEmpty { continue } // Has restrictions, not truly generic

            if let js = buildScriptletInvocation(rule) {
                jsFragments.append(js)
            }
        }

        return jsFragments.joined(separator: "\n")
    }

    /// Build an IIFE that invokes the AdGuard scriptlet function.
    private func buildScriptletInvocation(_ rule: ParsedScriptletRule) -> String? {
        // Look up the scriptlet function body by name
        guard let functionBody = scriptletLibrary[rule.name] else {
            // Try common alias transformations
            let altNames = [
                rule.name,
                "ubo-" + rule.name,
                rule.name + ".js",
                "ubo-" + rule.name + ".js"
            ]
            var body: String?
            for alt in altNames {
                if let found = scriptletLibrary[alt] {
                    body = found
                    break
                }
            }
            guard let resolvedBody = body else {
                abLog.warning("Unknown scriptlet: \(rule.name, privacy: .public)")
                return nil
            }
            return buildInvocationJS(functionBody: resolvedBody, rule: rule)
        }

        return buildInvocationJS(functionBody: functionBody, rule: rule)
    }

    private func buildInvocationJS(functionBody: String, rule: ParsedScriptletRule) -> String {
        let argsJSON: String
        if rule.args.isEmpty {
            argsJSON = "[]"
        } else {
            let escaped = rule.args.map { arg -> String in
                let s = arg
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                    .replacingOccurrences(of: "\n", with: "\\n")
                return "\"\(s)\""
            }
            argsJSON = "[\(escaped.joined(separator: ","))]"
        }

        // The source object expected by AdGuard scriptlets
        let domainName = rule.permittedDomains.first ?? ""
        let ruleText = rule.permittedDomains.joined(separator: ",") + "#%#//scriptlet(\"" + rule.name + "\")"

        return """
        (function() {
            \(functionBody)
            var source = {
                name: "\(rule.name.replacingOccurrences(of: "\"", with: "\\\""))",
                args: \(argsJSON),
                engine: "corelibs",
                verbose: false,
                domainName: "\(domainName.replacingOccurrences(of: "\"", with: "\\\""))",
                ruleText: "\(ruleText.replacingOccurrences(of: "\"", with: "\\\""))",
                uniqueId: "\(UUID().uuidString)"
            };
            var func_name = Object.keys(this).length === 0 ? undefined : Object.values(this).find(v => typeof v === 'function');
            var args = \(argsJSON);
            try {
                var scriptletFunc = \(extractFunctionName(from: functionBody));
                scriptletFunc.apply(this, [source].concat(args));
            } catch(e) {}
        })();
        """
    }

    /// Extract the function name from a function declaration like `function preventFetch(source, args) {`
    private func extractFunctionName(from functionBody: String) -> String {
        // Match "function SomeName(" pattern
        let pattern = #"^function\s+(\w+)\s*\("#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: functionBody, range: NSRange(functionBody.startIndex..., in: functionBody)),
           let nameRange = Range(match.range(at: 1), in: functionBody) {
            return String(functionBody[nameRange])
        }
        // Fallback: use anonymous function
        return "arguments.callee"
    }

    private func generateCSSInjectionJS(for host: String) -> String {
        if let cached = cssCache[host] { return cached }

        // Collect exception CSS rules for this domain
        var exceptionCSS: Set<String> = []
        for rule in cssRules where rule.isException {
            if domainMatches(host, permitted: rule.permittedDomains, restricted: rule.restrictedDomains) {
                exceptionCSS.insert(rule.css)
            }
        }

        var cssFragments: [String] = []

        for rule in cssRules {
            if rule.isException { continue }
            if exceptionCSS.contains(rule.css) { continue }
            if !domainMatches(host, permitted: rule.permittedDomains, restricted: rule.restrictedDomains) { continue }

            cssFragments.append(rule.css)
        }

        guard !cssFragments.isEmpty else {
            cssCache[host] = ""
            return ""
        }

        // Inject CSS via style element
        let escapedCSS = cssFragments.joined(separator: "\n")
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")

        let js = """
        (function() {
            var style = document.createElement('style');
            style.textContent = '\(escapedCSS)';
            (document.head || document.documentElement).appendChild(style);
        })();
        """

        cssCache[host] = js
        return js
    }

    private func generateCosmeticJS(for host: String) -> String {
        // Collect exception selectors for this domain
        var exceptionSelectors: Set<String> = []
        for rule in cosmeticRules where rule.isException {
            if domainMatches(host, permitted: rule.permittedDomains, restricted: rule.restrictedDomains) {
                exceptionSelectors.insert(rule.selector)
            }
        }

        var standardSelectors: [String] = []
        var extendedRules: [(selector: String, isExtendedCSS: Bool)] = []

        for rule in cosmeticRules {
            if rule.isException { continue }
            if exceptionSelectors.contains(rule.selector) { continue }
            if !domainMatches(host, permitted: rule.permittedDomains, restricted: rule.restrictedDomains) { continue }

            if rule.isExtendedCSS {
                extendedRules.append((rule.selector, true))
            } else {
                standardSelectors.append(rule.selector)
            }
        }

        var jsFragments: [String] = []

        // Standard CSS hiding
        if !standardSelectors.isEmpty {
            let escaped = standardSelectors.joined(separator: ", ")
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")

            jsFragments.append("""
            (function() {
                var style = document.createElement('style');
                style.textContent = '\(escaped) { display: none !important; }';
                (document.head || document.documentElement).appendChild(style);
            })();
            """)
        }

        // Extended CSS rules need a runtime interpreter — use MutationObserver-based approach
        if !extendedRules.isEmpty {
            let selectorsJSON = extendedRules.map { rule in
                let escaped = rule.selector
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                return "\"\(escaped)\""
            }.joined(separator: ",")

            jsFragments.append("""
            (function() {
                var selectors = [\(selectorsJSON)];
                function applyExtended() {
                    selectors.forEach(function(sel) {
                        try {
                            // Handle :has-text() pseudo-class
                            var hasTextMatch = sel.match(/^(.+?):has-text\\((.+?)\\)$/);
                            if (hasTextMatch) {
                                var baseSelector = hasTextMatch[1];
                                var textPattern = hasTextMatch[2];
                                var isRegex = textPattern.startsWith('/') && textPattern.endsWith('/');
                                document.querySelectorAll(baseSelector).forEach(function(el) {
                                    var text = el.textContent || '';
                                    var matches = isRegex
                                        ? new RegExp(textPattern.slice(1, -1)).test(text)
                                        : text.includes(textPattern);
                                    if (matches) el.style.setProperty('display', 'none', 'important');
                                });
                                return;
                            }
                            // Handle :upward() pseudo-class
                            var upwardMatch = sel.match(/^(.+?):upward\\((\\d+|.+?)\\)$/);
                            if (upwardMatch) {
                                var base = upwardMatch[1];
                                var arg = upwardMatch[2];
                                document.querySelectorAll(base).forEach(function(el) {
                                    var target = el;
                                    if (/^\\d+$/.test(arg)) {
                                        for (var i = 0; i < parseInt(arg) && target; i++) target = target.parentElement;
                                    } else {
                                        target = el.closest(arg);
                                    }
                                    if (target) target.style.setProperty('display', 'none', 'important');
                                });
                                return;
                            }
                            // Handle :remove() pseudo-class
                            var removeMatch = sel.match(/^(.+?):remove\\(\\)$/);
                            if (removeMatch) {
                                document.querySelectorAll(removeMatch[1]).forEach(function(el) { el.remove(); });
                                return;
                            }
                            // Fallback: try as standard selector
                            document.querySelectorAll(sel).forEach(function(el) {
                                el.style.setProperty('display', 'none', 'important');
                            });
                        } catch(e) {}
                    });
                }
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', applyExtended);
                } else {
                    applyExtended();
                }
                var observer = new MutationObserver(function() { applyExtended(); });
                var startObserving = function() {
                    observer.observe(document.documentElement || document.body, { childList: true, subtree: true });
                };
                if (document.body) startObserving();
                else document.addEventListener('DOMContentLoaded', startObserving);
            })();
            """)
        }

        return jsFragments.joined(separator: "\n")
    }

    // MARK: - Argument Parsing Utilities

    /// Parse comma-separated quoted arguments from a scriptlet rule.
    /// Handles: "name", "arg1", "arg2" — with proper quote escaping.
    private func parseQuotedArgs(_ input: String) -> [String] {
        var args: [String] = []
        var current = ""
        var inQuote = false
        var quoteChar: Character = "\""
        var escape = false

        let trimmed = input.trimmingCharacters(in: .whitespaces)

        for ch in trimmed {
            if escape {
                current.append(ch)
                escape = false
                continue
            }

            if ch == "\\" {
                escape = true
                continue
            }

            if !inQuote {
                if ch == "\"" || ch == "'" {
                    inQuote = true
                    quoteChar = ch
                } else if ch == "," {
                    let arg = current.trimmingCharacters(in: .whitespaces)
                    if !arg.isEmpty { args.append(arg) }
                    current = ""
                }
                // Skip whitespace outside quotes
            } else {
                if ch == quoteChar {
                    inQuote = false
                    // Don't append the closing quote
                } else {
                    current.append(ch)
                }
            }
        }

        let lastArg = current.trimmingCharacters(in: .whitespaces)
        if !lastArg.isEmpty { args.append(lastArg) }

        return args
    }
}
