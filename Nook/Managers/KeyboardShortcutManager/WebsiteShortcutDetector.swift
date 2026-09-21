// Licensed under GPL-3.0. See LICENSE.
//
//  WebsiteShortcutDetector.swift
//  Nook
//
//  Created by AI Assistant on 2025.
//
//  Detects keyboard shortcut conflicts between Nook and websites.
//  Implements the "double-press" system: first press goes to website,
//  second press within 1 second goes to Nook.
//

import Foundation
import AppKit
import WebKit

// MARK: - Website Shortcut Detector

@MainActor
@Observable
class WebsiteShortcutDetector {
    
    // MARK: - Properties
    
    /// The currently detected website profile based on URL
    private(set) var currentProfile: WebsiteShortcutProfile?
    
    /// The current URL being monitored
    private(set) var currentURL: URL?
    
    /// Pending shortcut presses waiting for a second press (windowId -> pending info)
    private var pendingShortcuts: [UUID: PendingShortcut] = [:]
    
    /// Cache of detected shortcuts from JS injection (host -> Set of lookup keys)
    private var jsDetectedShortcuts: [String: Set<String>] = [:]
    /// Hosts in the order they were first cached, so the cache can drop its oldest entry.
    private var jsDetectedHostOrder: [String] = []
    
    /// The timeout duration for double-press detection (1 second as specified)
    let conflictTimeout: TimeInterval = 1.0
    
    /// Weak reference to browser manager for notifications
    weak var browserManager: BrowserManager?

    // MARK: - Initialization

    private let instrumentedWebViews = NSHashTable<WKWebView>.weakObjects()
    @ObservationIgnored
    nonisolated(unsafe) private var settingsObserver: NSObjectProtocol?
    private var detectionEnabled = WebsiteShortcutProfile.isFeatureEnabled

    init() {
        settingsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let enabled = WebsiteShortcutProfile.isFeatureEnabled
                guard enabled != self.detectionEnabled else { return }
                self.detectionEnabled = enabled
                self.jsDetectedShortcuts.removeAll()
                self.jsDetectedHostOrder.removeAll()
                self.clearAllPendingShortcuts()
                for webView in self.instrumentedWebViews.allObjects {
                    self.configure(webView: webView)
                }
            }
        }
    }

    deinit {
        if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) }
    }

    func configure(webView: WKWebView) {
        instrumentedWebViews.add(webView)
        let script = WebsiteShortcutProfile.isFeatureEnabled
            ? Self.jsDetectionScript
            : "window.__nookStopShortcutDetection?.();"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }
    
    // MARK: - Public Interface
    
    /// Update the current website profile based on URL
    /// Called when the active tab's URL changes
    func updateCurrentURL(_ url: URL?) {
        currentURL = url
        
        // Find matching profile
        if let url = url {
            let matchedProfile = WebsiteShortcutProfile.knownProfiles.first { $0.matches(url: url) }
            currentProfile = matchedProfile
        } else {
            currentProfile = nil
        }
    }
    
    /// Check if a key combination is a known website shortcut
    /// Returns the website shortcut info if found, nil otherwise
    /// `allowPageReports` is false for shortcuts a page's own report must not claim.
    func isKnownWebsiteShortcut(_ keyCombination: KeyCombination, allowPageReports: Bool = true) -> WebsiteShortcut? {
        guard WebsiteShortcutProfile.isFeatureEnabled else { 
            return nil 
        }
        
        
        // Check known profile first
        if let profile = currentProfile,
           let shortcut = profile.hasShortcut(matching: keyCombination) {
            return shortcut
        }
        
        // Check JS-detected shortcuts
        if allowPageReports,
           let host = currentURL?.host,
           let detectedKeys = jsDetectedShortcuts[host],
           detectedKeys.contains(keyCombination.lookupKey) {
            // Return a generic detected shortcut
            return WebsiteShortcut(key: keyCombination.key, modifiers: keyCombination.modifiers, description: nil)
        }
        
        return nil
    }
    
    /// Determine if this key press should pass through to the website
    /// Returns true if this is the FIRST press of a conflicting shortcut
    /// Also triggers the conflict toast and sets pending state
    func shouldPassToWebsite(
        _ keyCombination: KeyCombination,
        windowId: UUID,
        nookActionName: String,
        allowPageReports: Bool
    ) -> Bool {
        guard WebsiteShortcutProfile.isFeatureEnabled else {
            return false
        }

        guard let websiteShortcut = isKnownWebsiteShortcut(keyCombination, allowPageReports: allowPageReports) else {
            return false
        }

        // Clean up expired entries on-demand instead of polling
        cleanupExpiredPendingShortcuts()

        let now = Date()
        
        // Check if there's already a pending shortcut for this window
        if let pending = pendingShortcuts[windowId],
           pending.keyCombination == keyCombination,
           now.timeIntervalSince(pending.timestamp) <= conflictTimeout {
            // This is the SECOND press within timeout - clear pending and return false
            // so Nook can capture it
            pendingShortcuts.removeValue(forKey: windowId)
            return false
        }
        
        // This is the FIRST press - set pending state and show toast
        let websiteName = currentProfile?.name ?? "Website"
        pendingShortcuts[windowId] = PendingShortcut(
            keyCombination: keyCombination,
            timestamp: now,
            websiteName: websiteName
        )
        
        // Show conflict toast via notification
        let conflictInfo = ShortcutConflictInfo(
            keyCombination: keyCombination,
            websiteName: websiteName,
            websiteShortcutDescription: websiteShortcut.description,
            nookActionName: nookActionName,
            windowId: windowId
        )
        postConflictNotification(conflictInfo)
        
        return true
    }
    
    /// Check if there's a pending shortcut for the given window
    func hasPendingShortcut(for windowId: UUID) -> Bool {
        cleanupExpiredPendingShortcuts()
        guard let pending = pendingShortcuts[windowId] else { return false }
        return Date().timeIntervalSince(pending.timestamp) <= conflictTimeout
    }
    
    /// Clear pending shortcut for a window (e.g., when switching tabs)
    func clearPendingShortcut(for windowId: UUID) {
        pendingShortcuts.removeValue(forKey: windowId)
    }
    
    /// Clear all pending shortcuts
    func clearAllPendingShortcuts() {
        pendingShortcuts.removeAll()
    }
    
    /// Update JS-detected shortcuts for a URL's host
    /// Called from Tab when JS injection reports detected listeners
    func updateJSDetectedShortcuts(for url: String, shortcuts: Set<String>) {
        guard let host = URL(string: url)?.host else { return }
        // Keyed by host and capped: a single-page app reports under a new URL on every route.
        if jsDetectedShortcuts.updateValue(shortcuts, forKey: host) == nil {
            jsDetectedHostOrder.append(host)
            if jsDetectedHostOrder.count > 200 {
                jsDetectedShortcuts.removeValue(forKey: jsDetectedHostOrder.removeFirst())
            }
        }
    }
    
    // MARK: - Private Methods

    private func cleanupExpiredPendingShortcuts() {
        let now = Date()
        let expiredWindows = pendingShortcuts.filter { now.timeIntervalSince($0.value.timestamp) > 1.5 }
            .map { $0.key }
        
        for windowId in expiredWindows {
            pendingShortcuts.removeValue(forKey: windowId)
        }
    }
    
    private func postConflictNotification(_ info: ShortcutConflictInfo) {
        NotificationCenter.default.post(
            name: .shortcutConflictDetected,
            object: nil,
            userInfo: ["conflictInfo": info]
        )
    }
}

// MARK: - Pending Shortcut

private struct PendingShortcut {
    let keyCombination: KeyCombination
    let timestamp: Date
    let websiteName: String
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a keyboard shortcut conflict is detected
    /// UserInfo contains "conflictInfo": ShortcutConflictInfo
    static let shortcutConflictDetected = Notification.Name("shortcutConflictDetected")
    
    /// Posted when a shortcut conflict toast should be dismissed
    static let shortcutConflictDismissed = Notification.Name("shortcutConflictDismissed")
}

// MARK: - JS Detection Script

extension WebsiteShortcutDetector {
    
    /// JavaScript to inject into web pages for runtime shortcut detection
    /// This attempts to detect keydown listeners that websites register
    static var jsDetectionScript: String {
        """
        (function() {
            // Only run once per page
            if (window.__nookShortcutDetectionActive) return;
            window.__nookShortcutDetectionActive = true;
            let active = true;
            
            // Track detected shortcuts
            const detectedShortcuts = new Set();
            
            // Hook into addEventListener to catch keydown/keyup listeners
            const originalAddEventListener = EventTarget.prototype.addEventListener;
            EventTarget.prototype.addEventListener = function(type, listener, options) {
                if (active && type === 'keydown') {
                    // Try to parse the listener to extract key combinations
                    // This is best-effort and won't catch all cases
                    try {
                        const listenerStr = listener.toString();
                        
                        // Look for patterns like e.key === 'k', e.code === 'KeyK', etc.
                        const keyMatches = listenerStr.match(/(?:e|event)\\.key\\s*===\\s*['"]([\\w]+)['"]/g);
                        const codeMatches = listenerStr.match(/(?:e|event)\\.code\\s*===\\s*['"]([\\w]+)['"]/g);
                        
                        if (keyMatches) {
                            keyMatches.forEach(m => {
                                const key = m.match(/['"]([\\w]+)['"]/)?.[1]?.toLowerCase();
                                if (key) detectedShortcuts.add(key);
                            });
                        }
                        
                        // Look for modifier checks
                        const hasCmd = listenerStr.includes('.metaKey') || listenerStr.includes('.ctrlKey');
                        const hasShift = listenerStr.includes('.shiftKey');
                        const hasAlt = listenerStr.includes('.altKey');
                        const hasCtrl = listenerStr.includes('.ctrlKey') && !listenerStr.includes('.metaKey');
                        
                        // Store modifier patterns for later
                        if (hasCmd || hasShift || hasAlt || hasCtrl) {
                            // Mark that this listener uses modifiers
                            window.__nookUsesModifiers = true;
                        }
                    } catch (e) {
                        // Ignore parsing errors
                    }
                }
                if (active && type === 'keydown') scheduleReport();
                return originalAddEventListener.call(this, type, listener, options);
            };
            
            // Keep only live accesskey nodes, updating changed subtrees rather than
            // rescanning the entire document for every mutation batch.
            const accessKeys = new Map();
            let reportTimer = null;
            let lastReport = null;
            function updateNode(node) {
                if (node.nodeType !== 1) return;
                const key = node.getAttribute('accesskey')?.toLowerCase();
                if (node.isConnected && key?.length === 1) accessKeys.set(node, 'accesskey:' + key);
                else accessKeys.delete(node);
            }
            function scanSubtree(node) {
                updateNode(node);
                node.querySelectorAll?.('[accesskey]').forEach(updateNode);
            }
            function scheduleReport() {
                if (reportTimer !== null) return;
                reportTimer = setTimeout(reportShortcuts, 100);
            }
            function reportShortcuts() {
                reportTimer = null;
                const keys = new Set([...detectedShortcuts, ...accessKeys.values()]);
                const report = Array.from(keys).sort().join(',');
                if (report !== lastReport) {
                    lastReport = report;
                    window.webkit?.messageHandlers?.nookShortcutDetect?.postMessage(report);
                }
            }
            scanSubtree(document.documentElement);
            const observer = new MutationObserver(mutations => {
                let removed = false;
                for (const mutation of mutations) {
                    if (mutation.type === 'attributes') updateNode(mutation.target);
                    else {
                        mutation.addedNodes.forEach(scanSubtree);
                        removed ||= mutation.removedNodes.length > 0;
                    }
                }
                if (removed) {
                    for (const node of accessKeys.keys()) {
                        if (!node.isConnected) accessKeys.delete(node);
                    }
                }
                scheduleReport();
            });
            observer.observe(document.documentElement, {
                childList: true, subtree: true, attributes: true, attributeFilter: ['accesskey']
            });
            const hookedAddEventListener = EventTarget.prototype.addEventListener;
            window.__nookStopShortcutDetection = function() {
                window.__nookShortcutDetectionActive = false;
                active = false;
                observer.disconnect();
                clearTimeout(reportTimer);
                accessKeys.clear();
                detectedShortcuts.clear();
                // Preserve wrappers installed by the website after ours.
                if (EventTarget.prototype.addEventListener === hookedAddEventListener) {
                    EventTarget.prototype.addEventListener = originalAddEventListener;
                }
            };
            scheduleReport();
        })();
        """
    }
}