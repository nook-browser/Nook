// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+SwitcherSnapshot.swift
//  NookWeb
//
//  The picture the Control-Tab switcher shows for a tab: taken as the window moves off it, while
//  the page is still on screen and drawn, at thumbnail size so it costs little to keep.
//

import WebKit

extension PageSession {
    private static let switcherSnapshotWidth: CGFloat = 400

    func captureSwitcherSnapshot() {
        guard let webView, webView.window != nil, webView.bounds.width > 0 else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(Self.switcherSnapshotWidth))
        configuration.afterScreenUpdates = false
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            // A picture that arrives after the page unloaded would pin its memory again.
            if let image, self?.primaryWebView != nil { self?.switcherSnapshot = image }
        }
    }
}
