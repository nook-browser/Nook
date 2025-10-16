//
//  TweakSecurityValidator.swift
//  Nook
//
//  Security validation and sandboxing for user-provided tweak code.
//

import Foundation
import WebKit

class TweakSecurityValidator {
    static let shared = TweakSecurityValidator()

    private init() {}

    // MARK: - CSS Validation

    func validateCSS(_ css: String) -> CSSValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        // Check for potentially dangerous CSS properties
        let dangerousProperties = [
            "behavior", "expression", "javascript:", "vbscript:",
            "@import", "binding", "-moz-binding"
        ]

        for property in dangerousProperties {
            if css.lowercased().contains(property) {
                errors.append("CSS contains potentially dangerous property: \(property)")
            }
        }

        // Check for data URLs in CSS
        if css.lowercased().contains("data:") {
            warnings.append("CSS contains data URLs - ensure content is safe")
        }

        // Check for very large CSS
        if css.count > 100_000 {
            warnings.append("CSS is very large (>100KB) - may impact performance")
        }

        // Basic CSS syntax validation
        if !css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let hasValidStructure = validateCSSStructure(css)
            if !hasValidStructure {
                errors.append("CSS appears to have syntax errors")
            }
        }

        return CSSValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    private func validateCSSStructure(_ css: String) -> Bool {
        // Basic CSS structure validation
        // This is a simple check - in a production environment you might want more sophisticated parsing
        let pattern = #"^[^{]*\{[^}]*\}"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let range = NSRange(location: 0, length: css.utf16.count)
        return regex?.firstMatch(in: css, options: [], range: range) != nil
    }

    // MARK: - JavaScript Validation

    func validateJavaScript(_ js: String) -> JSValidationResult {
        var errors: [String] = []
        var warnings: [String] = []
        var sanitizedJS = js

        // Check for dangerous JavaScript patterns
        let dangerousPatterns = [
            "eval(", "Function(", "setTimeout(", "setInterval(",
            "document.write", "document.open", "document.close",
            "innerHTML", "outerHTML", "insertAdjacentHTML",
            "location.", "window.location", "document.location",
            "localStorage", "sessionStorage", "indexedDB",
            "XMLHttpRequest", "fetch(", "WebSocket",
            "Worker(", "SharedWorker(", "ServiceWorker",
            "alert(", "confirm(", "prompt(",
            "window.open", "document.open"
        ]

        for pattern in dangerousPatterns {
            if js.contains(pattern) {
                errors.append("JavaScript contains potentially dangerous function: \(pattern)")
            }
        }

        // Check for script injection attempts
        if js.lowercased().contains("<script") || js.lowercased().contains("javascript:") {
            errors.append("JavaScript contains script injection attempts")
        }

        // Check for access to browser APIs
        let browserAPIs = [
            "chrome.", "browser.", "safari.", "webkit.",
            "navigator.", "window.webkit", "window.chrome"
        ]

        for api in browserAPIs {
            if js.contains(api) {
                warnings.append("JavaScript attempts to access browser APIs: \(api)")
            }
        }

        // Check for very large JavaScript
        if js.count > 50_000 {
            warnings.append("JavaScript is very large (>50KB) - may impact performance")
        }

        // Check for infinite loop patterns
        if hasInfiniteLoopPattern(js) {
            errors.append("JavaScript may contain infinite loops")
        }

        // Basic syntax validation
        if !js.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !validateJSStructure(js) {
                errors.append("JavaScript has syntax errors")
            }
        }

        // Sanitize the JavaScript
        sanitizedJS = sanitizeJavaScript(js)

        return JSValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings,
            sanitizedCode: sanitizedJS
        )
    }

    private func validateJSStructure(_ js: String) -> Bool {
        // This is a very basic syntax check
        // In a production environment, you'd want a proper JavaScript parser
        let balancedBrackets = countBalancedBrackets(js)
        return balancedBrackets
    }

    private func countBalancedBrackets(_ js: String) -> Bool {
        var parentheses = 0
        var brackets = 0
        var braces = 0

        for char in js {
            switch char {
            case "(": parentheses += 1
            case ")": parentheses -= 1
            case "[": brackets += 1
            case "]": brackets -= 1
            case "{": braces += 1
            case "}": braces -= 1
            default: break
            }

            if parentheses < 0 || brackets < 0 || braces < 0 {
                return false
            }
        }

        return parentheses == 0 && brackets == 0 && braces == 0
    }

    private func hasInfiniteLoopPattern(_ js: String) -> Bool {
        let dangerousPatterns = [
            "while(true)",
            "for(;;)",
            "while (true)",
            "for (;;)",
            "setInterval(function(){",
            "setTimeout(function(){"
        ]

        for pattern in dangerousPatterns {
            if js.lowercased().contains(pattern) {
                return true
            }
        }

        return false
    }

    private func sanitizeJavaScript(_ js: String) -> String {
        var sanitized = js

        // Remove or replace dangerous patterns
        let replacements: [(String, String)] = [
            ("eval", "//eval"),
            ("Function(", "//Function("),
            ("setTimeout", "//setTimeout"),
            ("setInterval", "//setInterval"),
            ("document.write", "//document.write"),
            ("innerHTML", "//innerHTML"),
            ("outerHTML", "//outerHTML"),
            ("location.", "//location."),
            ("localStorage", "//localStorage"),
            ("sessionStorage", "//sessionStorage"),
            ("fetch(", "//fetch("),
            ("XMLHttpRequest", "//XMLHttpRequest"),
            ("WebSocket", "//WebSocket"),
            ("alert(", "//alert("),
            ("confirm(", "//confirm("),
            ("prompt(", "//prompt(")
        ]

        for (pattern, replacement) in replacements {
            sanitized = sanitized.replacingOccurrences(of: pattern, with: replacement)
        }

        return sanitized
    }

    // MARK: - CSS Selector Validation

    func validateCSSSelector(_ selector: String) -> SelectorValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        // Check for empty selector
        if selector.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("CSS selector cannot be empty")
            return SelectorValidationResult(isValid: false, errors: errors, warnings: warnings)
        }

        // Check for dangerous selectors
        let dangerousPatterns = [
            "javascript:", "vbscript:", "data:",
            "<script", "</script", "onclick", "onerror", "onload"
        ]

        for pattern in dangerousPatterns {
            if selector.lowercased().contains(pattern) {
                errors.append("CSS selector contains potentially dangerous content: \(pattern)")
            }
        }

        // Check for universal selectors that might impact performance
        if selector.contains("*") {
            warnings.append("Universal selector (*) may impact performance")
        }

        // Check for very complex selectors
        if selector.count > 1000 {
            warnings.append("CSS selector is very complex - may impact performance")
        }

        // Basic CSS selector validation
        do {
            // Try to create a WebKit CSS selector
            let _ = try CSSSelector(selector)
        } catch {
            errors.append("Invalid CSS selector syntax: \(error.localizedDescription)")
        }

        return SelectorValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    // MARK: - URL Pattern Validation

    func validateURLPattern(_ pattern: String) -> URLPatternValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        // Check for empty pattern
        if pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("URL pattern cannot be empty")
            return URLPatternValidationResult(isValid: false, errors: errors, warnings: warnings)
        }

        // Check for dangerous patterns
        let dangerousPatterns = [
            "javascript:", "vbscript:", "data:",
            "file://", "ftp://", "mailto:", "tel:"
        ]

        for dangerousPattern in dangerousPatterns {
            if pattern.lowercased().contains(dangerousPattern) {
                errors.append("URL pattern contains potentially dangerous protocol: \(dangerousPattern)")
            }
        }

        // Validate URL pattern format
        if !isValidURLPattern(pattern) {
            errors.append("Invalid URL pattern format")
        }

        // Check for overly broad patterns
        if pattern == "*" || pattern == "*://*/*" {
            warnings.append("URL pattern matches all websites - ensure this is intentional")
        }

        return URLPatternValidationResult(
            isValid: errors.isEmpty,
            errors: errors,
            warnings: warnings
        )
    }

    private func isValidURLPattern(_ pattern: String) -> Bool {
        // Simple validation - could be enhanced
        let validChars = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: ".*-_/?:#[]@!$&'()*+,;="))

        return pattern.unicodeScalars.allSatisfy { validChars.contains($0) }
    }

    // MARK: - Security Policy Generation

    func generateSecurityPolicy() -> String {
        return """
        // Nook Tweaks Security Policy
        // This script enforces security restrictions for user-provided code

        (function() {
            'use strict';

            // Override dangerous functions
            const dangerousFunctions = [
                'eval', 'Function', 'setTimeout', 'setInterval',
                'XMLHttpRequest', 'fetch', 'WebSocket', 'Worker'
            ];

            dangerousFunctions.forEach(funcName => {
                if (typeof window[funcName] !== 'undefined') {
                    window[funcName] = function() {
                        console.warn('[Nook Tweaks Security] Blocked access to dangerous function:', funcName);
                        throw new Error('Access to ' + funcName + ' is not allowed in user scripts');
                    };
                }
            });

            // Override dangerous properties
            const dangerousProperties = [
                'innerHTML', 'outerHTML', 'location', 'localStorage', 'sessionStorage'
            ];

            dangerousProperties.forEach(propName => {
                Object.defineProperty(HTMLElement.prototype, propName, {
                    get: function() {
                        console.warn('[Nook Tweaks Security] Blocked access to property:', propName);
                        return '';
                    },
                    set: function(value) {
                        console.warn('[Nook Tweaks Security] Blocked write to property:', propName);
                        throw new Error('Setting ' + propName + ' is not allowed in user scripts');
                    }
                });
            });

            // Override dangerous methods
            const dangerousMethods = [
                'document.write', 'document.open', 'document.close',
                'alert', 'confirm', 'prompt', 'window.open'
            ];

            dangerousMethods.forEach(methodPath => {
                const parts = methodPath.split('.');
                let obj = window;
                for (let i = 0; i < parts.length - 1; i++) {
                    obj = obj[parts[i]];
                }
                const methodName = parts[parts.length - 1];

                if (obj && obj[methodName]) {
                    obj[methodName] = function() {
                        console.warn('[Nook Tweaks Security] Blocked access to method:', methodPath);
                        throw new Error('Access to ' + methodPath + ' is not allowed in user scripts');
                    };
                }
            });

            // Add safe DOM manipulation methods
            window.nookSafeDOM = {
                hideElement: function(selector) {
                    try {
                        const elements = document.querySelectorAll(selector);
                        elements.forEach(el => el.style.display = 'none');
                        return elements.length;
                    } catch (error) {
                        console.error('[Nook Tweaks] Error hiding elements:', error);
                        return 0;
                    }
                },

                showElement: function(selector) {
                    try {
                        const elements = document.querySelectorAll(selector);
                        elements.forEach(el => el.style.display = '');
                        return elements.length;
                    } catch (error) {
                        console.error('[Nook Tweaks] Error showing elements:', error);
                        return 0;
                    }
                },

                addCSS: function(css) {
                    try {
                        const style = document.createElement('style');
                        style.textContent = css;
                        style.setAttribute('data-nook-tweak', 'user-css');
                        document.head.appendChild(style);
                        return true;
                    } catch (error) {
                        console.error('[Nook Tweaks] Error adding CSS:', error);
                        return false;
                    }
                },

                addClass: function(selector, className) {
                    try {
                        const elements = document.querySelectorAll(selector);
                        elements.forEach(el => el.classList.add(className));
                        return elements.length;
                    } catch (error) {
                        console.error('[Nook Tweaks] Error adding class:', error);
                        return 0;
                    }
                },

                removeClass: function(selector, className) {
                    try {
                        const elements = document.querySelectorAll(selector);
                        elements.forEach(el => el.classList.remove(className));
                        return elements.length;
                    } catch (error) {
                        console.error('[Nook Tweaks] Error removing class:', error);
                        return 0;
                    }
                }
            };

            console.log('[Nook Tweaks] Security policy loaded');
        })();
        """
    }
}

// MARK: - Validation Result Types

struct CSSValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
}

struct JSValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
    let sanitizedCode: String
}

struct SelectorValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
}

struct URLPatternValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
}

// MARK: - CSS Selector Helper
private struct CSSSelector {
    let selector: String

    init(_ selector: String) throws {
        // This is a placeholder - in a real implementation you'd want
        // proper CSS selector validation using WebKit's internal APIs
        self.selector = selector

        // Basic validation
        if selector.isEmpty {
            throw NSError(domain: "CSSSelector", code: 1, userInfo: [NSLocalizedDescriptionKey: "Empty selector"])
        }

        if selector.contains("<script") || selector.contains("javascript:") {
            throw NSError(domain: "CSSSelector", code: 2, userInfo: [NSLocalizedDescriptionKey: "Dangerous content in selector"])
        }
    }
}