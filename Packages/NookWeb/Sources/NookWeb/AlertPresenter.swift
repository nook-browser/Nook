// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  AlertPresenter.swift
//  NookWeb
//
//  The native panels a page can ask for. Each is presented over the window showing `webView`.
//

import WebKit

@MainActor
public protocol AlertPresenter: AnyObject {
    // `host` is the frame that asked, so an iframe cannot speak as the page embedding it. A
    // non-nil `onSuppress` means offer "no more dialogs" and call it, before `completion`, if
    // the user takes it.
    func presentAlert(
        message: String, host: String, over webView: WKWebView,
        onSuppress: (() -> Void)?, completion: @escaping () -> Void)
    func presentConfirm(
        message: String, host: String, over webView: WKWebView,
        onSuppress: (() -> Void)?, completion: @escaping (Bool) -> Void)
    func presentPrompt(
        prompt: String, defaultText: String?, host: String, over webView: WKWebView,
        onSuppress: (() -> Void)?, completion: @escaping (String?) -> Void)
    func presentOpenPanel(
        allowsMultipleSelection: Bool, allowsDirectories: Bool, over webView: WKWebView,
        completion: @escaping ([URL]?) -> Void)
}
