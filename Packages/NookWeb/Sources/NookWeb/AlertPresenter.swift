//
//  AlertPresenter.swift
//  NookWeb
//
//  The native panels a page can ask for. Each is presented over the window showing `webView`.
//

import WebKit

@MainActor
public protocol AlertPresenter: AnyObject {
    func presentAlert(message: String, over webView: WKWebView, completion: @escaping () -> Void)
    func presentConfirm(message: String, over webView: WKWebView, completion: @escaping (Bool) -> Void)
    func presentPrompt(
        prompt: String, defaultText: String?, over webView: WKWebView,
        completion: @escaping (String?) -> Void)
    func presentOpenPanel(
        allowsMultipleSelection: Bool, allowsDirectories: Bool, over webView: WKWebView,
        completion: @escaping ([URL]?) -> Void)
}
