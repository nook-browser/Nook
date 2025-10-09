//
//  WebStoreScriptHandler.swift
//  Nook
//
//  Message handler for Chrome Web Store integration
//

import Foundation
import WebKit
import AppKit

@MainActor
final class WebStoreScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var browserManager: BrowserManager?
    
    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
        super.init()
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "nookWebStore" else { return }
        
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              action == "installExtension",
              let extensionId = body["extensionId"] as? String else {
            return
        }
        
        // Install the extension
        if #available(macOS 15.5, *), let extensionManager = browserManager?.extensionManager {
            extensionManager.installFromWebStore(extensionId: extensionId) { result in
                Task { @MainActor in
                    // Notify the web page of completion
                    let success = if case .success = result { true } else { false }
                    let script = """
                    window.dispatchEvent(new CustomEvent('nookInstallComplete', { 
                        detail: { 
                            success: \(success),
                            extensionId: '\(extensionId)'
                        } 
                    }));
                    """
                    
                    if let webView = message.webView {
                        webView.evaluateJavaScript(script)
                    }
                    
                    switch result {
                    case .success(let ext):
                        self.showSuccessNotification(extensionName: ext.name)
                    case .failure(let error):
                        self.showErrorNotification(error: error)
                    }
                }
            }
        } else {
            showErrorNotification(error: ExtensionError.unsupportedOS)
        }
    }
    
    private func showSuccessNotification(extensionName: String) {
        let alert = NSAlert()
        alert.messageText = "Extension Installed"
        alert.informativeText = "\"\(extensionName)\" has been installed successfully and is ready to use."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        
        // Show non-modal
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
    
    private func showErrorNotification(error: Error) {
        let alert = NSAlert()
        alert.messageText = "Installation Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        
        // Show non-modal
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}

