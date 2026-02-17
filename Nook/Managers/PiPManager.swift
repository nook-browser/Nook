//
//  PiPManager.swift
//  Nook
//
//  Picture-in-Picture implementation using WebKit APIs.
//  Supports web video PiP via standard WebKit presentation mode APIs.
//

import Foundation
import AppKit
import WebKit

@MainActor
final class PiPManager: NSObject {
    static let shared = PiPManager()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Web Video PiP
    
    func requestPiP(for tab: Tab, webView: WKWebView? = nil) {
        // Use assignedWebView to avoid triggering lazy initialization
        // PiP only works on tabs that are currently displayed
        let targetWebView = webView ?? tab.assignedWebView
        guard let webView = targetWebView else {
            print("[PiP] No webView available (tab not displayed)")
            return
        }
        
        let pipToggleScript = """
        (function() {
            const video = document.querySelector('video');
            if (!video) return { success: false, error: 'No video found' };
            
            try {
                // WebKit presentation mode (Safari/macOS)
                if (video.webkitSupportsPresentationMode && typeof video.webkitSetPresentationMode === 'function') {
                    const currentMode = video.webkitPresentationMode || 'inline';
                    const newMode = (currentMode === 'picture-in-picture') ? 'inline' : 'picture-in-picture';
                    video.webkitSetPresentationMode(newMode);
                    return { success: true, mode: newMode };
                }
                
                // Standard PiP API fallback
                if (document.pictureInPictureEnabled && video.requestPictureInPicture) {
                    if (document.pictureInPictureElement) {
                        document.exitPictureInPicture();
                        return { success: true, mode: 'inline' };
                    } else {
                        video.requestPictureInPicture().catch(function(err) {
                            console.log('PiP request failed:', err);
                        });
                        return { success: true, mode: 'picture-in-picture' };
                    }
                }
                
                return { success: false, error: 'PiP not supported on this page' };
            } catch (error) {
                return { success: false, error: error.message };
            }
        })();
        """
        
        webView.evaluateJavaScript(pipToggleScript) { result, error in
            if let error = error {
                print("[PiP] JavaScript error: \(error.localizedDescription)")
                return
            }
            
            if let resultDict = result as? [String: Any] {
                if let success = resultDict["success"] as? Bool, success {
                    if let mode = resultDict["mode"] as? String {
                        let isPiPActive = (mode == "picture-in-picture")
                        tab.hasPiPActive = isPiPActive
                        print("[PiP] Web PiP toggled to: \(mode)")
                    }
                } else if let errorMsg = resultDict["error"] as? String {
                    print("[PiP] Web PiP failed: \(errorMsg)")
                }
            }
        }
    }
    
    func stopPiP(for tab: Tab, webView: WKWebView? = nil) {
        // Use assignedWebView to avoid triggering lazy initialization
        let targetWebView = webView ?? tab.assignedWebView
        guard let webView = targetWebView else { 
            print("[PiP] No webView available for stopping PiP")
            tab.hasPiPActive = false
            return 
        }
        
        // Check if webView is still valid and can execute JavaScript
        guard webView.navigationDelegate != nil else {
            print("[PiP] WebView delegate is nil, skipping PiP stop")
            tab.hasPiPActive = false
            return
        }
        
        let stopWebPiPScript = """
        (function() {
            try {
                const video = document.querySelector('video');
                if (video) {
                    if (video.webkitSupportsPresentationMode && video.webkitPresentationMode === 'picture-in-picture') {
                        video.webkitSetPresentationMode('inline');
                    } else if (document.pictureInPictureElement) {
                        document.exitPictureInPicture();
                    }
                }
                return { success: true };
            } catch (error) {
                return { success: false, error: error.message };
            }
        })();
        """
        
        webView.evaluateJavaScript(stopWebPiPScript) { result, error in
            if let error = error {
                print("[PiP] Error stopping web PiP: \(error.localizedDescription)")
            } else if let resultDict = result as? [String: Any] {
                if let success = resultDict["success"] as? Bool, !success {
                    if let errorMsg = resultDict["error"] as? String {
                        print("[PiP] JavaScript error stopping PiP: \(errorMsg)")
                    }
                }
            }
        }
        
        tab.hasPiPActive = false
    }
    
    func isPiPActive(for tab: Tab) -> Bool {
        return tab.hasPiPActive
    }
}
