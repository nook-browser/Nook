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
    
    /// Cache of detected shortcuts from JS injection (URL -> Set of lookup keys)
    private var jsDetectedShortcuts: [String: Set<String>] = [:]
    
    /// The timeout duration for double-press detection (1 second as specified)
    let conflictTimeout: TimeInterval = 1.0
    
    /// Timer for cleaning up expired pending shortcuts
    nonisolated(unsafe) private var cleanupTimer: Timer?
    
    /// Weak reference to browser manager for notifications
    weak var browserManager: BrowserManager?
    
    // MARK: - Initialization
    
    init() {
        startCleanupTimer()
    }
    
    deinit {
        cleanupTimer?.invalidate()
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
            print("⌨️ [Detector] URL updated: \(url.host ?? "nil"), matched profile: \(matchedProfile?.name ?? "none")")
        } else {
            currentProfile = nil
            print("⌨️ [Detector] URL cleared, no profile")
        }
    }
    
    /// Check if a key combination is a known website shortcut
    /// Returns the website shortcut info if found, nil otherwise
    func isKnownWebsiteShortcut(_ keyCombination: KeyCombination) -> WebsiteShortcut? {
        guard WebsiteShortcutProfile.isFeatureEnabled else { 
            print("⌨️ [Detector] Feature disabled, not checking shortcuts")
            return nil 
        }
        
        print("⌨️ [Detector] Checking shortcut: \(keyCombination.lookupKey)")
        print("⌨️ [Detector] Current URL: \(currentURL?.host ?? "nil")")
        print("⌨️ [Detector] Current profile: \(currentProfile?.name ?? "nil")")
        
        // Check known profile first
        if let profile = currentProfile,
           let shortcut = profile.hasShortcut(matching: keyCombination) {
            print("⌨️ [Detector] ✅ Found matching shortcut in profile: \(profile.name)")
            return shortcut
        }
        
        // Check JS-detected shortcuts
        if let urlKey = currentURL?.absoluteString,
           let detectedKeys = jsDetectedShortcuts[urlKey],
           detectedKeys.contains(keyCombination.lookupKey) {
            print("⌨️ [Detector] ✅ Found matching shortcut in JS-detected: \(keyCombination.lookupKey)")
            // Return a generic detected shortcut
            return WebsiteShortcut(key: keyCombination.key, modifiers: keyCombination.modifiers, description: nil)
        }
        
        print("⌨️ [Detector] ❌ No matching shortcut found")
        return nil
    }
    
    /// Determine if this key press should pass through to the website
    /// Returns true if this is the FIRST press of a conflicting shortcut
    /// Also triggers the conflict toast and sets pending state
    func shouldPassToWebsite(
        _ keyCombination: KeyCombination,
        windowId: UUID,
        nookActionName: String
    ) -> Bool {
        guard WebsiteShortcutProfile.isFeatureEnabled else { 
            print("⌨️ [Detector] Feature disabled, not passing through")
            return false 
        }
        
        guard let websiteShortcut = isKnownWebsiteShortcut(keyCombination) else { 
            print("⌨️ [Detector] No matching website shortcut for: \(keyCombination.lookupKey)")
            return false 
        }
        
        let now = Date()
        
        // Check if there's already a pending shortcut for this window
        if let pending = pendingShortcuts[windowId],
           pending.keyCombination == keyCombination,
           now.timeIntervalSince(pending.timestamp) <= conflictTimeout {
            // This is the SECOND press within timeout - clear pending and return false
            // so Nook can capture it
            print("⌨️ [Detector] SECOND press detected - capturing for Nook")
            pendingShortcuts.removeValue(forKey: windowId)
            return false
        }
        
        // This is the FIRST press - set pending state and show toast
        let websiteName = currentProfile?.name ?? "Website"
        print("⌨️ [Detector] FIRST press - passing to website: \(websiteName)")
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
    
    /// Update JS-detected shortcuts for a URL
    /// Called from Tab when JS injection reports detected listeners
    func updateJSDetectedShortcuts(for url: String, shortcuts: Set<String>) {
        jsDetectedShortcuts[url] = shortcuts
    }
    
    // MARK: - Private Methods
    
    private func startCleanupTimer() {
        // Clean up expired pending shortcuts every 500ms
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupExpiredPendingShortcuts()
            }
        }
    }
    
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
            
            // Track detected shortcuts
            const detectedShortcuts = new Set();
            
            // Hook into addEventListener to catch keydown/keyup listeners
            const originalAddEventListener = EventTarget.prototype.addEventListener;
            EventTarget.prototype.addEventListener = function(type, listener, options) {
                if (type === 'keydown') {
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
                return originalAddEventListener.call(this, type, listener, options);
            };
            
            // Also try to detect accesskey attributes
            function checkAccessKeys() {
                const elements = document.querySelectorAll('[accesskey]');
                elements.forEach(el => {
                    const key = el.getAttribute('accesskey')?.toLowerCase();
                    if (key && key.length === 1) {
                        detectedShortcuts.add('accesskey:' + key);
                    }
                });
            }
            
            // Check accesskeys after DOM loads
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', checkAccessKeys);
            } else {
                checkAccessKeys();
            }
            
            // Monitor for dynamic accesskey additions
            const observer = new MutationObserver(() => checkAccessKeys());
            observer.observe(document.body || document.documentElement, { 
                childList: true, 
                subtree: true,
                attributes: true,
                attributeFilter: ['accesskey']
            });
            
            // Report detected shortcuts to native
            function reportShortcuts() {
                if (window.webkit?.messageHandlers?.nookShortcutDetect && detectedShortcuts.size > 0) {
                    window.webkit.messageHandlers.nookShortcutDetect.postMessage(
                        Array.from(detectedShortcuts).join(',')
                    );
                }
            }
            
            // Report periodically and on visibility change
            setInterval(reportShortcuts, 5000);
            document.addEventListener('visibilitychange', reportShortcuts);
            
            // Initial report after a short delay
            setTimeout(reportShortcuts, 1000);
        })();
        """
    }
}