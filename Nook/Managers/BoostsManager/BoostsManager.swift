//
//  BoostsManager.swift
//  Nook
//
//  Created by Claude on 11/11/2025.
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
}

@MainActor
class BoostsManager: ObservableObject {
    @Published private(set) var boosts: [String: BoostConfig] = [:]

    private let userDefaults = UserDefaults.standard
    private let boostsKey = "nook_domain_boosts"

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
        boosts[normalizedDomain] = config
        persistBoosts()
    }

    /// Remove boost for a domain
    func removeBoost(for domain: String) {
        let normalizedDomain = normalizeDomain(domain)
        boosts.removeValue(forKey: normalizedDomain)
        persistBoosts()
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
                }
            } else {
                // DarkReader already loaded, just apply config
                self.applyBoostConfig(config, to: webView, completion: completion)
            }
        }
    }

    /// Get JavaScript code to apply boost configuration
    func getBoostApplyScript(for config: BoostConfig) -> String {
        // Convert percentages to 0-1 range for DarkReader
        let brightness = config.brightness
        let contrast = config.contrast
        let sepia = config.sepia
        let tintStrength = config.tintStrength

        return """
            (function() {
                if (typeof DarkReader !== 'undefined') {
                    DarkReader.disable();
                    DarkReader.enable({
                        brightness: \(brightness),
                        contrast: \(contrast),
                        sepia: \(sepia),
                        mode: \(config.mode),
                        tintColor: '\(config.tintColor)',
                        tintStrength: \(tintStrength)
                    });
                    console.log('✅ [Nook Boost] Applied boost:', {brightness: \(brightness), contrast: \(contrast), sepia: \(sepia), tintColor: '\(config.tintColor)', tintStrength: \(tintStrength)});
                } else {
                    console.error('❌ [Nook Boost] DarkReader not loaded');
                }
            })();
            """
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
