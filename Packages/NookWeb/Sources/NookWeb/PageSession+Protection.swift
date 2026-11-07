// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+Protection.swift
//  Nook
//

import WebKit

extension PageSession {
    /// Enhanced fingerprinting protection unless it was turned off for the current site.
    public var usesEnhancedFingerprintingProtection: Bool {
        enhancedFingerprintingProtectionOffHost == nil && enhancedFingerprintingProtectionApplies
    }

    public var enhancedFingerprintingProtectionApplies: Bool {
        controller?.settings.enhancedFingerprintingProtection.applies(inPrivateWindow: isPrivate) == true
    }

    public var removesTrackingFromLinks: Bool {
        controller?.settings.removeTrackingFromLinks.applies(inPrivateWindow: isPrivate) == true
    }

    public func reloadWithoutEnhancedFingerprintingProtection() {
        enhancedFingerprintingProtectionOffHost = url.host
        refresh()
    }

    public func reloadWithEnhancedFingerprintingProtection() {
        enhancedFingerprintingProtectionOffHost = nil
        refresh()
    }

    func applyProtection(to preferences: WKWebpagePreferences, for url: URL) {
        guard let settings = controller?.settings else { return }
        if let host = enhancedFingerprintingProtectionOffHost, host != url.host { enhancedFingerprintingProtectionOffHost = nil }
        preferences.setAdvancedPrivacyProtections(
            enhancedFingerprinting: usesEnhancedFingerprintingProtection,
            linkFiltering: removesTrackingFromLinks
        )
        // WebKit loads a blank page instead of its warning for loopback and private addresses.
        preferences.preferredHTTPSNavigationPolicy = settings.warnBeforeHTTP && !DevHosts.isDevHost(url)
            ? .userMediatedFallbackToHTTP
            : .automaticFallbackToHTTP
    }
}

extension WKWebpagePreferences {
    /// Safari's Advanced Tracking and Fingerprinting Protection, in two parts. WebKit names the
    /// option bits after unrelated features: `EnhancedTelemetry` is enhanced fingerprinting protection,
    /// `RequestValidation` enhanced network privacy and `SanitizeLookalikeCharacters` link filtering.
    fileprivate func setAdvancedPrivacyProtections(enhancedFingerprinting: Bool, linkFiltering: Bool) {
        let getter = NSSelectorFromString("_networkConnectionIntegrityPolicy")
        let setter = NSSelectorFromString("_setNetworkConnectionIntegrityPolicy:")
        guard responds(to: getter), responds(to: setter) else { return }
        let baseline: UInt = 1 << 0
        let enhancedTelemetry: UInt = 1 << 6
        let requestValidation: UInt = 1 << 7
        let sanitizeLookalikeCharacters: UInt = 1 << 8
        let enhancedFingerprintingBits = baseline | enhancedTelemetry | requestValidation

        typealias Getter = @convention(c) (AnyObject, Selector) -> UInt
        typealias Setter = @convention(c) (AnyObject, Selector, UInt) -> Void
        var policy = unsafeBitCast(method(for: getter), to: Getter.self)(self, getter)
        policy &= ~(enhancedFingerprintingBits | sanitizeLookalikeCharacters)
        if enhancedFingerprinting { policy |= enhancedFingerprintingBits }
        if linkFiltering { policy |= sanitizeLookalikeCharacters }
        unsafeBitCast(method(for: setter), to: Setter.self)(self, setter, policy)
    }
}
