// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  ZoomManager.swift
//  Nook
//
//  Created by Assistant on 13/10/2025.
//

import Foundation
import WebKit

@Observable
@MainActor
class ZoomManager {
    private static let presets: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    private var tabZoomLevels: [UUID: Double] = [:]

    var currentZoomLevel: Double = 1.0

    var currentZoomPercentage: Int { Int(currentZoomLevel * 100) }

    var isAtMinimumZoom: Bool { currentZoomLevel <= 0.5 }

    var isAtMaximumZoom: Bool { currentZoomLevel >= 2.0 }

    func getZoomPercentageDisplay() -> String {
        return "\(currentZoomPercentage)%"
    }

    // MARK: - Public Methods

    /// Apply a zoom level to a web view.
    func applyZoom(_ zoomLevel: Double, to webView: WKWebView, tabId: UUID) {
        let clampedZoom = max(0.5, min(2.0, zoomLevel))

        // pageZoom relays the page out, so text and canvases re-render sharp. magnification is a
        // layer scale a stray trackpad pinch leaves behind, and it resamples canvas-drawn pages.
        webView.pageZoom = clampedZoom
        webView.magnification = 1.0

        tabZoomLevels[tabId] = clampedZoom
        currentZoomLevel = clampedZoom
    }

    func zoomIn(for webView: WKWebView, tabId: UUID) {
        applyZoom(nextZoomLevel(from: zoomLevel(for: tabId), direction: .up), to: webView, tabId: tabId)
    }

    func zoomOut(for webView: WKWebView, tabId: UUID) {
        applyZoom(nextZoomLevel(from: zoomLevel(for: tabId), direction: .down), to: webView, tabId: tabId)
    }

    /// Back to 100%. Also runs on navigation, so a page never inherits the last one's zoom.
    func resetZoom(for webView: WKWebView, tabId: UUID) {
        applyZoom(1.0, to: webView, tabId: tabId)
    }

    /// Points the displayed level at `tabId`. Zoom is per tab, the readout is one value.
    func showZoomLevel(for tabId: UUID?) {
        currentZoomLevel = tabId.map { zoomLevel(for: $0) } ?? 1.0
    }

    /// Remove the zoom level for a closed tab
    func removeTabZoomLevel(for tabId: UUID) {
        tabZoomLevels.removeValue(forKey: tabId)
    }

    // MARK: - Private

    private func zoomLevel(for tabId: UUID) -> Double {
        return tabZoomLevels[tabId] ?? 1.0
    }

    /// Nearest preset in the given direction; the tolerance skips the current level.
    private func nextZoomLevel(from currentLevel: Double, direction: ZoomDirection) -> Double {
        switch direction {
        case .up:
            return Self.presets.first { $0 > currentLevel + 0.01 } ?? 2.0
        case .down:
            return Self.presets.last { $0 < currentLevel - 0.01 } ?? 0.5
        }
    }
}

// MARK: - Supporting Types

private enum ZoomDirection {
    case up
    case down
}
