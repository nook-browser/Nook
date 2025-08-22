//
//  PiPManager.swift
//  Pulse
//
//  Picture-in-Picture implementation following expert recommendations.
//  Supports both web video PiP via WebKit APIs and native video PiP via AVKit.
//

import Foundation
import AppKit
import AVFoundation
import AVKit
import WebKit

@MainActor
final class PiPManager: NSObject {
    static let shared = PiPManager()
    
    // For native video PiP using AVKit
    private struct NativePiPSession {
        weak var tab: Tab?
        let player: AVPlayer
        let playerLayer: AVPlayerLayer
        var pipController: AVPictureInPictureController?
        var floatingWindow: NSWindow?
    }
    
    private var nativeSession: NativePiPSession?
    
    private override init() {
        super.init()
    }
    
    // MARK: - Web Video PiP (for WKWebView content)
    
    func requestWebPiP(for tab: Tab) {
        guard let webView = tab.webView else {
            print("[PiP] No webView available")
            return
        }
        
        let pipToggleScript = """
        (function() {
          const video = document.querySelector('video');
          if (!video) return { success: false, error: 'No video found' };
        
          try {
            // Safari/WebKit (macOS) - synchronous
            if (video.webkitSupportsPresentationMode && typeof video.webkitSetPresentationMode === 'function') {
              const currentMode = video.webkitPresentationMode || 'inline';
              const newMode = (currentMode === 'picture-in-picture') ? 'inline' : 'picture-in-picture';
              video.webkitSetPresentationMode(newMode);
              return { success: true, mode: newMode };
            }
        
            // Standard PiP API fallback - this will be async but we'll handle it
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
                // Fallback to native PiP if web PiP fails
                self.tryNativePiPFallback(for: tab, webView: webView)
            } else if let resultDict = result as? [String: Any] {
                if let success = resultDict["success"] as? Bool, success {
                    if let mode = resultDict["mode"] as? String {
                        print("[PiP] Web PiP toggled to: \(mode)")
                        let isPiPActive = (mode == "picture-in-picture")
                        tab.hasPiPActive = isPiPActive
                        
                        // Notify that PiP state changed
                        if isPiPActive {
                            print("[PiP] PiP activated - background playback enabled")
                        } else {
                            print("[PiP] PiP deactivated")
                        }
                    }
                } else if let errorMsg = resultDict["error"] as? String {
                    print("[PiP] Web PiP failed: \(errorMsg)")
                    // Fallback to native PiP
                    self.tryNativePiPFallback(for: tab, webView: webView)
                }
            } else {
                print("[PiP] Unexpected result from JavaScript: \(String(describing: result))")
                // Fallback to native PiP
                self.tryNativePiPFallback(for: tab, webView: webView)
            }
        }
    }
    
    // MARK: - Native Video PiP (for direct media URLs)
    
    private func tryNativePiPFallback(for tab: Tab, webView: WKWebView) {
        // Try to extract a direct media URL from the page
        let mediaExtractionScript = """
        (function(){
          function abs(u){ try { return new URL(u, document.baseURI).href; } catch(_) { return null; } }
          const vids = Array.from(document.querySelectorAll('video'));
          
          // Look for the first playing or ready video
          for (const v of vids){
            if (v.readyState >= 2) { // HAVE_CURRENT_DATA or better
              let u = v.currentSrc || v.src;
              if (!u && v.querySelector) { 
                const s = v.querySelector('source[src]'); 
                if (s) u = s.src; 
              }
              if (u && !u.startsWith('blob:') && !u.startsWith('data:')){
                const a = abs(u); 
                if (a && (a.startsWith('http://') || a.startsWith('https://'))) {
                  return { url: a, title: document.title || 'Video' };
                }
              }
            }
          }
          
          // Fallback: try any video with a source
          for (const v of vids){
            let u = v.currentSrc || v.src;
            if (!u && v.querySelector) { 
              const s = v.querySelector('source[src]'); 
              if (s) u = s.src; 
            }
            if (u && !u.startsWith('blob:') && !u.startsWith('data:')){
              const a = abs(u); 
              if (a && (a.startsWith('http://') || a.startsWith('https://'))) {
                return { url: a, title: document.title || 'Video' };
              }
            }
          }
          
          return null;
        })();
        """
        
        webView.evaluateJavaScript(mediaExtractionScript) { [weak self] result, error in
            guard let self = self else { return }
            
            if let error = error {
                print("[PiP] Media extraction error: \(error.localizedDescription)")
                return
            }
            
            if let resultDict = result as? [String: Any],
               let urlString = resultDict["url"] as? String,
               let url = URL(string: urlString) {
                let title = resultDict["title"] as? String ?? "Video"
                print("[PiP] Fallback to native PiP with URL: \(urlString) (\(title))")
                self.startNativePiP(with: url, for: tab)
            } else if let urlString = result as? String, let url = URL(string: urlString) {
                // Backward compatibility
                print("[PiP] Fallback to native PiP with URL: \(urlString)")
                self.startNativePiP(with: url, for: tab)
            } else {
                print("[PiP] No suitable media URL found for native PiP fallback. Found: \(String(describing: result))")
            }
        }
    }
    
    func startNativePiP(with url: URL, for tab: Tab) {
        // Stop any existing native session
        stopNativePiP()
        
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        let playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        
        // Try AVPictureInPictureController first (macOS 12+)
        if #available(macOS 12.0, *) {
            let contentSource = AVPictureInPictureController.ContentSource(playerLayer: playerLayer)
            if AVPictureInPictureController.isPictureInPictureSupported() {
                let pipController = AVPictureInPictureController(contentSource: contentSource)
                pipController.delegate = self
                
                nativeSession = NativePiPSession(
                    tab: tab,
                    player: player,
                    playerLayer: playerLayer,
                    pipController: pipController,
                    floatingWindow: nil
                )
                
                player.play()
                
                if pipController.isPictureInPicturePossible {
                    pipController.startPictureInPicture()
                    tab.hasPiPActive = true
                    print("[PiP] Native PiP activated - background playback enabled")
                    return
                }
            }
        }
        
        // Fallback: floating AVPlayerView window
        createFloatingPlayerWindow(with: player, playerLayer: playerLayer, for: tab)
    }
    
    private func createFloatingPlayerWindow(with player: AVPlayer, playerLayer: AVPlayerLayer, for tab: Tab) {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .inline
        playerView.showsFullScreenToggleButton = false
        
        if #available(macOS 12.0, *) {
            playerView.allowsPictureInPicturePlayback = true
        }
        
        playerView.frame = NSRect(x: 0, y: 0, width: 480, height: 270)
        
        let window = NSPanel(
            contentRect: playerView.frame,
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Pulse PiP"
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hasShadow = true
        window.center()
        window.contentView = playerView
        
        nativeSession = NativePiPSession(
            tab: tab,
            player: player,
            playerLayer: playerLayer,
            pipController: nil,
            floatingWindow: window
        )
        
        player.play()
        window.makeKeyAndOrderFront(nil)
        tab.hasPiPActive = true
        print("[PiP] Native PiP window activated - background playback enabled")
    }
    
    func stopNativePiP() {
        guard let session = nativeSession else { return }
        
        session.pipController?.stopPictureInPicture()
        session.floatingWindow?.orderOut(nil)
        session.player.pause()
        session.tab?.hasPiPActive = false
        print("[PiP] Native PiP deactivated")
        
        nativeSession = nil
    }
    
    func isNativePiPActive(for tab: Tab) -> Bool {
        guard let session = nativeSession, session.tab?.id == tab.id else { return false }
        
        if let pipController = session.pipController {
            return pipController.isPictureInPictureActive
        }
        
        if let window = session.floatingWindow {
            return window.isVisible
        }
        
        return false
    }
    
    // MARK: - Public Interface
    
    func requestPiP(for tab: Tab) {
        // First try web-based PiP (preferred for web content)
        requestWebPiP(for: tab)
    }
    
    func stopPiP(for tab: Tab) {
        // Stop native PiP if active
        if isNativePiPActive(for: tab) {
            stopNativePiP()
        }
        
        // Also try to stop web PiP
        guard let webView = tab.webView else { return }
        
        let stopWebPiPScript = """
        const video = document.querySelector('video');
        if (video) {
          if (video.webkitSupportsPresentationMode && video.webkitPresentationMode === 'picture-in-picture') {
            video.webkitSetPresentationMode('inline');
          } else if (document.pictureInPictureElement) {
            document.exitPictureInPicture();
          }
        }
        """
        
        webView.evaluateJavaScript(stopWebPiPScript) { _, error in
            if let error = error {
                print("[PiP] Error stopping web PiP: \(error.localizedDescription)")
            }
        }
        
        tab.hasPiPActive = false
    }
    
    func isPiPActive(for tab: Tab) -> Bool {
        return isNativePiPActive(for: tab) || tab.hasPiPActive
    }
}

// MARK: - AVPictureInPictureControllerDelegate

@MainActor
extension PiPManager: @preconcurrency AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[PiP] Native PiP will start")
    }
    
    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[PiP] Native PiP did start")
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        print("[PiP] Native PiP failed to start: \(error.localizedDescription)")
        nativeSession?.tab?.hasPiPActive = false
    }
    
    func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[PiP] Native PiP will stop")
    }
    
    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        print("[PiP] Native PiP did stop")
        nativeSession?.tab?.hasPiPActive = false
        nativeSession = nil
    }
    
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(true)
    }
}