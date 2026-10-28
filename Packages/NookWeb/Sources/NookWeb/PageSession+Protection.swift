// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+Protection.swift
//  Nook
//

import WebKit

extension PageSession {
    /// Strict unless Reload with Standard Protection lifted it for the current site.
    public var usesStrictProtection: Bool {
        reducedProtectionHost == nil && strictProtectionApplies
    }

    public func reloadWithStandardProtection() {
        reducedProtectionHost = url.host
        refresh()
    }

    private var strictProtectionApplies: Bool {
        switch controller?.settings.protectionLevel {
        case .strict: return true
        case .strictInPrivate: return isPrivate
        case .standard, nil: return false
        }
    }

    func applyProtection(to preferences: WKWebpagePreferences, for url: URL) {
        guard let settings = controller?.settings else { return }
        if let host = reducedProtectionHost, host != url.host { reducedProtectionHost = nil }
        preferences.setAdvancedPrivacyProtections(usesStrictProtection)
        // WebKit loads a blank page instead of its warning for loopback and private addresses.
        preferences.preferredHTTPSNavigationPolicy = settings.warnBeforeHTTP && !DevHosts.isDevHost(url)
            ? .userMediatedFallbackToHTTP
            : .automaticFallbackToHTTP
    }

    func applyPrivacySettings(to webView: WKWebView) {
        guard let settings = controller?.settings else { return }
        webView.configuration.preferences.isFraudulentWebsiteWarningEnabled = settings.fraudulentWebsiteWarning
        webView.configuration.websiteDataStore.setTrackingPreventionEnabled(settings.preventCrossSiteTracking)
    }
}

extension WKWebpagePreferences {
    /// Safari's Advanced Tracking and Fingerprinting Protection: known-tracker blocking, fingerprinting
    /// defenses, link tracking-parameter removal and enhanced network privacy.
    fileprivate func setAdvancedPrivacyProtections(_ enabled: Bool) {
        let selector = NSSelectorFromString("_setNetworkConnectionIntegrityEnabled:")
        guard responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(method(for: selector), to: Setter.self)(self, selector, enabled)
    }
}

extension WKWebsiteDataStore {
    fileprivate func setTrackingPreventionEnabled(_ enabled: Bool) {
        let selector = NSSelectorFromString("_setResourceLoadStatisticsEnabled:")
        guard responds(to: selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
        unsafeBitCast(method(for: selector), to: Setter.self)(self, selector, enabled)
    }
}
