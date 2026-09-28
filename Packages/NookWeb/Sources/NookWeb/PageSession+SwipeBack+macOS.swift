// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+SwipeBack+macOS.swift
//  NookWeb
//
//  A two-finger swipe back on a page with no history returns to the tab that opened it.
//

#if os(macOS)
import AppKit
import WebKit

extension PageSession {
    /// WebKit's own swipe needs a back item, so it never starts here. It reports only the wheel
    /// events the page did not scroll with, so a carousel or map under the pointer keeps its swipe.
    /// The progress range copies WebKit's (`ViewGestureController`).
    @objc(_webView:didNotHandleWheelEvent:)
    func webView(_ webView: WKWebView, didNotHandleWheelEvent event: NSEvent) {
        guard event.phase == .began, event.hasPreciseScrollingDeltas,
              NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              abs(event.scrollingDeltaY) < abs(event.scrollingDeltaX) / 2,
              !webView.canGoBack, controller?.opener(of: itemID) != nil else { return }
        let rightToLeft = webView.userInterfaceLayoutDirection == .rightToLeft
        guard rightToLeft ? event.scrollingDeltaX < 0 : event.scrollingDeltaX > 0 else { return }
        var cancelled = false
        event.trackSwipeEvent(
            options: [.lockDirection, .clampGestureAmount],
            dampenAmountThresholdMin: rightToLeft ? -1 : 0, max: rightToLeft ? 0 : 1
        ) { [weak self, weak webView] amount, phase, isComplete, _ in
            guard let webView else { return }
            webView.layer?.setAffineTransform(CGAffineTransform(translationX: amount * webView.bounds.width, y: 0))
            if phase == .cancelled { cancelled = true }
            guard isComplete else { return }
            // Close first, so a finished swipe does not flash the page back into place.
            if !cancelled { self?.goBack(in: webView) }
            webView.layer?.setAffineTransform(.identity)
        }
    }
}
#endif
