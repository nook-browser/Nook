// Licensed under GPL-3.0. See LICENSE.
//
//  ZoomManager.swift
//  Nook
//
//  Created by Jonathan Caudill on 13/10/2025.
//

import Foundation
import WebKit

@Observable
@MainActor
class ZoomManager {
    // Match the familiar browser zoom ladder. In particular, the first step down
    // from the default 100% is 90%, not 75%.
    private static let presets: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0]
    private static let defaultsKey = "siteZoomLevels"

    /// Zoom per host, kept across launches. Only levels other than 100% are stored.
    private var siteZoomLevels = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:]
    /// Private windows' levels, never written to disk.
    private var privateZoomLevels: [String: Double] = [:]

    var currentZoomLevel: Double = 1.0

    var currentZoomPercentage: Int { Int(currentZoomLevel * 100) }

    var isAtMinimumZoom: Bool { currentZoomLevel <= 0.5 }

    var isAtMaximumZoom: Bool { currentZoomLevel >= 2.0 }

    func getZoomPercentageDisplay() -> String {
        return "\(currentZoomPercentage)%"
    }

    // MARK: - Public Methods

    /// Apply a zoom level to a web view and remember it for the page's site.
    func applyZoom(_ zoomLevel: Double, to webView: WKWebView) {
        let clampedZoom = max(0.5, min(2.0, zoomLevel))
        setPageZoom(clampedZoom, on: webView)
        currentZoomLevel = clampedZoom

        guard let host = webView.url?.host() else { return }
        let stored = clampedZoom == 1.0 ? nil : clampedZoom
        if webView.configuration.websiteDataStore.isPersistent {
            siteZoomLevels[host] = stored
            UserDefaults.standard.set(siteZoomLevels, forKey: Self.defaultsKey)
        } else {
            privateZoomLevels[host] = stored
        }
    }

    func zoomIn(for webView: WKWebView) {
        applyZoom(nextZoomLevel(from: webView.pageZoom, direction: .up), to: webView)
    }

    func zoomOut(for webView: WKWebView) {
        applyZoom(nextZoomLevel(from: webView.pageZoom, direction: .down), to: webView)
    }

    func resetZoom(for webView: WKWebView) {
        applyZoom(1.0, to: webView)
    }

    /// Applies the saved level for the page's site. Runs on every commit.
    func restoreZoom(for webView: WKWebView) {
        let levels = webView.configuration.websiteDataStore.isPersistent ? siteZoomLevels : privateZoomLevels
        setPageZoom(webView.url?.host().flatMap { levels[$0] } ?? 1.0, on: webView)
    }

    /// Points the readout at the page being looked at.
    func showZoomLevel(for webView: WKWebView?) {
        currentZoomLevel = webView.map { Double($0.pageZoom) } ?? 1.0
    }

    // MARK: - Private

    private func setPageZoom(_ zoom: Double, on webView: WKWebView) {
        // pageZoom relays the page out, so text and canvases re-render sharp. magnification is a
        // layer scale a stray trackpad pinch leaves behind, and it resamples canvas-drawn pages.
        if webView.pageZoom != zoom { webView.pageZoom = zoom }
        webView.magnification = 1.0
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
