//
//  PageSession+Media.swift
//  Nook
//
//  Media, audio, picture-in-picture and page color state for a PageSession.
//

import CoreAudio
import SwiftUI
import WebKit

extension PageSession {
    // MARK: - Simple Media Detection (mainly for manual checks)
    public func checkMediaState() {
        // Get all web views for this tab across all windows
        let allWebViews: [WKWebView]
        if let coordinator = controller?.webViews {
            allWebViews = coordinator.allWebViews(for: itemID)
        } else if let webView = primaryWebView {
            // Fallback to original web view for backward compatibility
            allWebViews = [webView]
        } else {
            return
        }

        // Simple state check - optimized single-pass version
        let mediaCheckScript = """
            (() => {
                const audios = document.querySelectorAll('audio');
                const videos = document.querySelectorAll('video');

                // Single pass through audios
                const hasPlayingAudio = Array.from(audios).some(audio =>
                    !audio.paused && !audio.ended && audio.readyState >= 2
                );

                // Single pass through videos for all checks
                let hasPlayingVideoWithAudio = false;
                let hasPlayingVideo = false;

                Array.from(videos).forEach(video => {
                    const isPlaying = !video.paused && !video.ended && video.readyState >= 2;
                    if (isPlaying) {
                        hasPlayingVideo = true;
                        if (!video.muted && video.volume > 0) {
                            hasPlayingVideoWithAudio = true;
                        }
                    }
                });

                const hasAudioContent = hasPlayingAudio || hasPlayingVideoWithAudio;

                return {
                    hasAudioContent: hasAudioContent,
                    hasPlayingAudio: hasAudioContent,
                    hasVideoContent: videos.length > 0,
                    hasPlayingVideo: hasPlayingVideo
                };
            })();
            """

        // Check media state across all web views and aggregate results
        var aggregatedResults: [String: Bool] = [
            "hasAudioContent": false,
            "hasPlayingAudio": false,
            "hasVideoContent": false,
            "hasPlayingVideo": false,
        ]

        let group = DispatchGroup()

        for webView in allWebViews {
            group.enter()
            webView.evaluateJavaScript(mediaCheckScript) { result, error in
                defer { group.leave() }

                if let error = error {
                    return
                }

                if let state = result as? [String: Bool] {
                    // Aggregate results - if any web view has media, the tab has media
                    aggregatedResults["hasAudioContent"] =
                        (aggregatedResults["hasAudioContent"] ?? false)
                        || (state["hasAudioContent"] ?? false)
                    aggregatedResults["hasPlayingAudio"] =
                        (aggregatedResults["hasPlayingAudio"] ?? false)
                        || (state["hasPlayingAudio"] ?? false)
                    aggregatedResults["hasVideoContent"] =
                        (aggregatedResults["hasVideoContent"] ?? false)
                        || (state["hasVideoContent"] ?? false)
                    aggregatedResults["hasPlayingVideo"] =
                        (aggregatedResults["hasPlayingVideo"] ?? false)
                        || (state["hasPlayingVideo"] ?? false)
                }
            }
        }

        // Update tab state after all web views have been checked
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.hasAudioContent = aggregatedResults["hasAudioContent"] ?? false
            self.hasPlayingAudio = aggregatedResults["hasPlayingAudio"] ?? false
            self.hasVideoContent = aggregatedResults["hasVideoContent"] ?? false
            self.hasPlayingVideo = aggregatedResults["hasPlayingVideo"] ?? false
        }
    }

    public func toggleMute() {
        setMuted(!isAudioMuted)
    }

    public func setMuted(_ muted: Bool) {
        if let webView = primaryWebView {
            // Set the mute state using MuteableWKWebView's muted property
            webView.isMuted = muted
        } else {
        }

        controller?.sessionDelegate?.setMuteState(muted, for: itemID)

        // Update our internal state (already on main thread via @MainActor)
        isAudioMuted = muted
    }

    // MARK: - Native Audio Monitoring
    public func startNativeAudioMonitoring() {
        guard !isMonitoringNativeAudio else { return }
        isMonitoringNativeAudio = true

        audioMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkNativeAudioActivity() }
        }

        setupAudioSessionNotifications()
    }

    public func stopNativeAudioMonitoring() {
        guard isMonitoringNativeAudio else { return }
        isMonitoringNativeAudio = false

        audioMonitoringTimer?.invalidate()
        audioMonitoringTimer = nil

        removeCoreAudioPropertyListeners()
    }

    public func setupAudioSessionNotifications() {
        setupCoreAudioPropertyListeners()
    }

    /// Helper class that holds a weak reference to the session for the Core Audio listener callback.
    /// Prevents dangling pointer if the session is deallocated before the listener is removed.
    public final class AudioListenerHelper {
        weak var session: PageSession?
        init(session: PageSession) { self.session = session }
    }

    public func setupCoreAudioPropertyListeners() {
        guard !hasAddedCoreAudioListener else { return }

        let helper = AudioListenerHelper(session: self)
        audioListenerHelper = helper

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        audioDeviceListenerProc = { (objectID, numAddresses, addresses, clientData) in
            guard let clientData = clientData else { return noErr }
            let helper = Unmanaged<AudioListenerHelper>.fromOpaque(clientData).takeUnretainedValue()

            if let session = helper.session {
                DispatchQueue.main.async {
                    session.checkNativeAudioActivity()
                }
            }

            return noErr
        }

        if let listenerProc = audioDeviceListenerProc {
            let status = AudioObjectAddPropertyListener(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                listenerProc,
                Unmanaged.passRetained(helper).toOpaque()
            )

            if status == noErr {
                hasAddedCoreAudioListener = true
            } else {
                // Registration failed — release the retained helper
                Unmanaged.passUnretained(helper).release()
            }
        }
    }

    public func removeCoreAudioPropertyListeners() {
        guard hasAddedCoreAudioListener, let listenerProc = audioDeviceListenerProc,
              let helper = audioListenerHelper else { return }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerProc,
            Unmanaged.passUnretained(helper).toOpaque()
        )

        if status == noErr {
            // Balance the passRetained from setup
            Unmanaged.passUnretained(helper).release()
            hasAddedCoreAudioListener = false
            audioDeviceListenerProc = nil
            audioListenerHelper = nil
        }
    }

    public func checkNativeAudioActivity() {
        let now = Date()
        guard now.timeIntervalSince(lastAudioDeviceCheckTime) > 0.5 else { return }
        lastAudioDeviceCheckTime = now

        let isDeviceActive = isDefaultAudioDeviceActive()

        if isDeviceActive && hasAudioContent {
            if !hasPlayingAudio {
                hasPlayingAudio = true
            }
        } else if hasPlayingAudio && !isDeviceActive {
            hasPlayingAudio = false
        }
    }

    public func isDefaultAudioDeviceActive() -> Bool {
        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        guard status == noErr else {
            return false
        }

        var isRunning: UInt32 = 0
        dataSize = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere

        let runningStatus = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &isRunning
        )

        return runningStatus == noErr && isRunning != 0
    }

    // MARK: - Background Color Management
    public func setupThemeColorObserver(for webView: WKWebView) {
        if !themeColorObservedWebViews.contains(webView) {
            webView.addObserver(
                self, forKeyPath: "themeColor", options: [.new, .initial], context: nil)
            themeColorObservedWebViews.add(webView)
        }
    }

    public func removeThemeColorObserver(from webView: WKWebView) {
        if themeColorObservedWebViews.contains(webView) {
            webView.removeObserver(self, forKeyPath: "themeColor")
            themeColorObservedWebViews.remove(webView)
        }
    }

    public func updateBackgroundColor(from webView: WKWebView) {
        // Check if we should sample based on domain change
        guard let currentURL = webView.url,
              let currentDomain = extractDomain(from: currentURL) else {
            // If no URL/domain, still try theme color but skip pixel sampling
            if let themeColor = webView.themeColor {
                pageBackgroundColor = themeColor
                webView.underPageBackgroundColor = themeColor
            }
            return
        }

        // Only sample if domain changed or we haven't sampled yet
        let shouldSample = lastSampledDomain != currentDomain

        var newColor: PlatformColor? = nil

        newColor = webView.themeColor

        if let themeColor = newColor {
            pageBackgroundColor = themeColor
            webView.underPageBackgroundColor = themeColor
            // Update sampled domain even for theme color
            if shouldSample {
                lastSampledDomain = currentDomain
            }
        } else if shouldSample {
            // Only extract via pixel sampling if domain changed
            extractBackgroundColorWithJavaScript(from: webView)
        }
    }
    
    /// Extract domain and subdomain from URL (e.g., "subdomain.example.com" -> "subdomain.example.com")
    public func extractDomain(from url: URL) -> String? {
        guard let host = url.host else { return nil }
        return host
    }

    public func extractBackgroundColorWithJavaScript(from webView: WKWebView) {
        guard let sampleRect = colorSampleRect(for: webView) else {
            runLegacyBackgroundColorScript(on: webView)
            return
        }

        let configuration = WKSnapshotConfiguration()
        configuration.rect = sampleRect
        configuration.afterScreenUpdates = true
        configuration.snapshotWidth = 1

        webView.takeSnapshot(with: configuration) { [weak self, weak webView] image, error in
            // takeSnapshot completion runs on main thread; no dispatch needed
            guard let self = self, let webView = webView else { return }

            if let color = image?.singlePixelColor {
                self.pageBackgroundColor = color
                webView.underPageBackgroundColor = color
                // Update sampled domain after successful extraction
                if let currentURL = webView.url,
                   let currentDomain = self.extractDomain(from: currentURL) {
                    self.lastSampledDomain = currentDomain
                }
            } else {
                self.runLegacyBackgroundColorScript(on: webView)
            }
        }
    }

    public func colorSampleRect(for webView: WKWebView) -> CGRect? {
        let bounds = webView.bounds
        guard bounds.width >= 1, bounds.height >= 1 else { return nil }

        var sampleX = bounds.midX
        sampleX = min(max(bounds.minX, sampleX), bounds.maxX - 1)

        let offset: CGFloat = 2.0
        let yCandidate: CGFloat
        if webView.isFlipped {
            yCandidate = bounds.minY + offset
        } else {
            yCandidate = bounds.maxY - offset - 1
        }
        let sampleY = min(max(yCandidate, bounds.minY), bounds.maxY - 1)

        return CGRect(x: sampleX, y: sampleY, width: 1, height: 1)
    }
    
    public func topRightPixelRect(for webView: WKWebView) -> CGRect? {
        let bounds = webView.bounds
        guard bounds.width >= 1, bounds.height >= 1 else { return nil }
        
        // Sample the top-rightmost pixel
        let sampleX = bounds.maxX - 1
        let sampleY: CGFloat
        if webView.isFlipped {
            // In flipped coordinates, minY is at the top
            sampleY = bounds.minY
        } else {
            // In non-flipped coordinates, maxY is at the top
            sampleY = bounds.maxY - 1
        }
        
        return CGRect(x: sampleX, y: sampleY, width: 1, height: 1)
    }
    
    public func extractTopBarColor(from webView: WKWebView) {
        // Only sample once per domain
        if let currentURL = webView.url,
           let domain = extractDomain(from: currentURL) {
            if lastTopBarDomain == domain { return }
            lastTopBarDomain = domain
        }

        guard let sampleRect = topRightPixelRect(for: webView) else {
            return
        }
        
        let configuration = WKSnapshotConfiguration()
        configuration.rect = sampleRect
        configuration.afterScreenUpdates = true
        configuration.snapshotWidth = 1
        
        webView.takeSnapshot(with: configuration) { [weak self] image, error in
            guard let self = self else { return }

            if let color = image?.singlePixelColor {
                self.topBarBackgroundColor = color
            }
        }
    }

    public func runLegacyBackgroundColorScript(on webView: WKWebView) {
        let colorExtractionScript = """
            (function() {
                function rgbToHex(r, g, b) {
                    return '#' + [r, g, b].map(x => {
                        const hex = x.toString(16);
                        return hex.length === 1 ? '0' + hex : hex;
                    }).join('');
                }

                function parseColor(color) {
                    const div = document.createElement('div');
                    div.style.color = color;
                    document.body.appendChild(div);
                    const computedColor = window.getComputedStyle(div).color;
                    document.body.removeChild(div);

                    const match = computedColor.match(/rgb\\((\\d+),\\s*(\\d+),\\s*(\\d+)\\)/);
                    if (match) {
                        return rgbToHex(parseInt(match[1]), parseInt(match[2]), parseInt(match[3]));
                    }
                    return null;
                }

                function extractBackgroundColor() {
                    const body = document.body;
                    const html = document.documentElement;

                    // Try body background first
                    let bodyBg = window.getComputedStyle(body).backgroundColor;
                    if (bodyBg && bodyBg !== 'rgba(0, 0, 0, 0)' && bodyBg !== 'transparent') {
                        return parseColor(bodyBg);
                    }

                    // Try html background
                    let htmlBg = window.getComputedStyle(html).backgroundColor;
                    if (htmlBg && htmlBg !== 'rgba(0, 0, 0, 0)' && htmlBg !== 'transparent') {
                        return parseColor(htmlBg);
                    }

                    // Try sampling dominant colors from visible elements
                    const sampleElements = [
                        document.querySelector('header'),
                        document.querySelector('nav'),
                        document.querySelector('main'),
                        document.querySelector('.container'),
                        document.querySelector('#main'),
                        document.querySelector('[class*="background"]'),
                        document.querySelector('[class*="bg"]')
                    ].filter(el => el);

                    for (const el of sampleElements) {
                        const bg = window.getComputedStyle(el).backgroundColor;
                        if (bg && bg !== 'rgba(0, 0, 0, 0)' && bg !== 'transparent') {
                            return parseColor(bg);
                        }
                    }

                    // Fallback: detect if page looks dark or light and return appropriate gray
                    const isDarkMode = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
                    const textColor = window.getComputedStyle(body).color;
                    const isLightText = textColor && (textColor.includes('255') || textColor.includes('white'));

                    if (isDarkMode || isLightText) {
                        return '#1a1a1a'; // Dark gray for dark themes
                    } else {
                        return '#ffffff'; // White for light themes
                    }
                }

                const bgColor = extractBackgroundColor();
                if (bgColor) {
                    window.webkit.messageHandlers['backgroundColor_\(itemID.uuidString)'].postMessage({
                        backgroundColor: bgColor
                    });
                }
            })();
            """

        webView.evaluateJavaScript(colorExtractionScript) { _, _ in }
    }

    public func requestPictureInPicture() {
        // In multi-window setup, we need to work with the WebView that's actually visible
        // in the current window, not just the first WebView created
        let activeWindowID = controller?.windowRegistry.activeWindow?.id
        let activeWebView = activeWindowID.flatMap { controller?.webViews?.webView(for: self.itemID, in: $0) }
        controller?.sessionDelegate?.requestPictureInPicture(for: self, webView: activeWebView)
    }

    public func pause() {
        if !hasPiPActive && controller?.sessionDelegate?.isPictureInPictureActive(for: self) != true {
            primaryWebView?.evaluateJavaScript(
                "document.querySelectorAll('video, audio').forEach(el => el.pause());",
                completionHandler: nil
            )
        }

        hasPlayingVideo = false
        hasPlayingAudio = false
    }
}
