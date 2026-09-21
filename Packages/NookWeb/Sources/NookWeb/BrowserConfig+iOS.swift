// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserConfig+iOS.swift
//  NookWeb
//
//  UIKit's configuration has real properties where AppKit needs KVC, and sites look for the
//  Mobile token to serve their phone layout.
//

#if os(iOS)
import WebKit

extension BrowserConfiguration {
    static func applyPlatformPreferences(to config: WKWebViewConfiguration) {
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.applicationNameForUserAgent = "Version/\(PlatformUserAgent.safariVersion) Mobile/15E148 Safari/604.1"
    }
}
#endif
