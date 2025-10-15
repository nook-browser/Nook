//
//  ZoomManager.swift
//  Nook
//
//  Created by Assistant on 13/10/2025.
//

import Foundation
import WebKit
import Combine

@Observable
@MainActor
class ZoomManager: ObservableObject {
    private let userDefaults = UserDefaults.standard
    private let zoomKeyPrefix = "zoom."

    // Zoom level presets
    static let zoomPresets: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    // Current zoom state for each tab
    private var tabZoomLevels: [UUID: Double] = [:]

    // Published properties for UI updates
    var currentZoomLevel: Double = 1.0
    var currentDomain: String?

    init() {}

    // MARK: - Public Methods

    /// Get zoom level for a specific domain
    func getZoomLevel(for domain: String) -> Double {
        let key = zoomKeyPrefix + domain
        return userDefaults.double(forKey: key)
    }

    /// Save zoom level for a specific domain
    func saveZoomLevel(_ zoomLevel: Double, for domain: String) {
        let key = zoomKeyPrefix + domain
        userDefaults.set(zoomLevel, forKey: key)
    }

    /// Get zoom level for a specific tab
    func getZoomLevel(for tabId: UUID) -> Double {
        return tabZoomLevels[tabId] ?? 1.0
    }

    /// Set zoom level for a specific tab
    func setZoomLevel(_ zoomLevel: Double, for tabId: UUID) {
        tabZoomLevels[tabId] = zoomLevel
        currentZoomLevel = zoomLevel
    }

    /// Apply zoom to WebView with persistence
    func applyZoom(_ zoomLevel: Double, to webView: WKWebView, domain: String?, tabId: UUID) {
        // Validate zoom level bounds
        let clampedZoom = max(0.5, min(2.0, zoomLevel))

        // Apply page zoom to WebView (this scales the content, not the view)
        webView.pageZoom = clampedZoom

        // Update tab zoom level
        setZoomLevel(clampedZoom, for: tabId)

        // Save for domain if available
        if let domain = domain {
            saveZoomLevel(clampedZoom, for: domain)
            currentDomain = domain
        }

        currentZoomLevel = clampedZoom
    }

    /// Zoom in for the current tab
    func zoomIn(for webView: WKWebView, domain: String?, tabId: UUID) {
        let currentLevel = getZoomLevel(for: tabId)
        let nextLevel = findNextZoomLevel(from: currentLevel, direction: .up)
        applyZoom(nextLevel, to: webView, domain: domain, tabId: tabId)
    }

    /// Zoom out for the current tab
    func zoomOut(for webView: WKWebView, domain: String?, tabId: UUID) {
        let currentLevel = getZoomLevel(for: tabId)
        let nextLevel = findNextZoomLevel(from: currentLevel, direction: .down)
        applyZoom(nextLevel, to: webView, domain: domain, tabId: tabId)
    }

    /// Reset zoom to 100%
    func resetZoom(for webView: WKWebView, domain: String?, tabId: UUID) {
        applyZoom(1.0, to: webView, domain: domain, tabId: tabId)
    }

    /// Load saved zoom level for a domain and apply to WebView (only for existing tabs, not new tabs)
    func loadSavedZoom(for webView: WKWebView, domain: String, tabId: UUID) {
        // Always start new tabs at 100% (actual size)
        // Don't load saved zoom for new tabs - this ensures sites always open at actual size
        applyZoom(1.0, to: webView, domain: domain, tabId: tabId)
        currentDomain = domain
    }

    /// Clear zoom level for a domain
    func clearZoomLevel(for domain: String) {
        let key = zoomKeyPrefix + domain
        userDefaults.removeObject(forKey: key)
    }

    /// Clear all saved zoom levels
    func clearAllZoomLevels() {
        let keys = userDefaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(zoomKeyPrefix) }
        for key in keys {
            userDefaults.removeObject(forKey: key)
        }
    }

    /// Get zoom percentage as string for display
    func getZoomPercentageDisplay() -> String {
        return "\(Int(currentZoomLevel * 100))%"
    }

    /// Find the closest zoom preset in the specified direction
    private func findNextZoomLevel(from currentLevel: Double, direction: ZoomDirection) -> Double {
        let presets = Self.zoomPresets.sorted()

        switch direction {
        case .up:
            // Find the next larger preset
            for preset in presets {
                if preset > currentLevel + 0.01 { // Add small tolerance to avoid exact matches
                    return preset
                }
            }
            // If no larger preset found, return the maximum
            return presets.last ?? 2.0

        case .down:
            // Find the next smaller preset
            for preset in presets.reversed() {
                if preset < currentLevel - 0.01 { // Add small tolerance to avoid exact matches
                    return preset
                }
            }
            // If no smaller preset found, return the minimum
            return presets.first ?? 0.5
        }
    }

    // MARK: - Cleanup

    /// Remove zoom level for a closed tab
    func removeTabZoomLevel(for tabId: UUID) {
        tabZoomLevels.removeValue(forKey: tabId)
    }

    /// Clear all tab-specific zoom levels (called on app quit)
    func clearAllTabZoomLevels() {
        tabZoomLevels.removeAll()
    }
}

// MARK: - Supporting Types

private enum ZoomDirection {
    case up    // Zoom in
    case down  // Zoom out
}

// MARK: - Extensions

extension ZoomManager {
    /// Get the current zoom level as a percentage
    var currentZoomPercentage: Int {
        return Int(currentZoomLevel * 100)
    }

    /// Check if the current zoom level is at the minimum
    var isAtMinimumZoom: Bool {
        return currentZoomLevel <= 0.5
    }

    /// Check if the current zoom level is at the maximum
    var isAtMaximumZoom: Bool {
        return currentZoomLevel >= 2.0
    }

    /// Check if the current zoom level is at the default (100%)
    var isAtDefaultZoom: Bool {
        return abs(currentZoomLevel - 1.0) < 0.01
    }
}