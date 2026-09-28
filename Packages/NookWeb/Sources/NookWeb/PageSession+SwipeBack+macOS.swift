// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+SwipeBack+macOS.swift
//  NookWeb
//
//  Trackpad swipes: back to the tab that opened a page with no history, and the snapshot WebKit
//  shows after a swipe.
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

    // MARK: - Swipe Snapshot

    /// After a swipe WebKit covers the page with a snapshot until the page restores its scroll
    /// position. A site that restores scroll itself (`history.scrollRestoration = "manual"`, as
    /// Reddit does) never reports that, so the page sat dead under the snapshot for WebKit's 3 s
    /// watchdog. Once the swipe has ended and the page is not loading, the snapshot goes.
    /// ponytail: fixed 300 ms wait; tune it if pages show half drawn or still feel slow.
    @objc(_webViewDidBeginNavigationGesture:)
    func webViewDidBeginNavigationGesture(_ webView: WKWebView) {
        navigationGestureCount += 1
    }

    @objc(_webViewDidEndNavigationGesture:withNavigationToBackForwardListItem:)
    func webViewDidEndNavigationGesture(_ webView: WKWebView, withNavigationTo item: WKBackForwardListItem?) {
        guard item != nil else { return }
        let gesture = navigationGestureCount
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300)) { [weak self, weak webView] in
            guard let self, let webView, gesture == self.navigationGestureCount, !webView.isLoading,
                  webView.callBool("_isShowingNavigationGestureSnapshot") == true else { return }
            // Testing SPI, but the only way in: it removes the snapshot once the swipe has ended.
            webView.callVoid("_resetNavigationGestureStateForTesting")
        }
    }
}

private extension WKWebView {
    func callBool(_ name: String) -> Bool? {
        let selector = NSSelectorFromString(name)
        guard responds(to: selector) else { return nil }
        typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(method(for: selector), to: Getter.self)(self, selector)
    }

    func callVoid(_ name: String) {
        let selector = NSSelectorFromString(name)
        guard responds(to: selector) else { return }
        typealias Call = @convention(c) (AnyObject, Selector) -> Void
        unsafeBitCast(method(for: selector), to: Call.self)(self, selector)
    }
}
#endif
