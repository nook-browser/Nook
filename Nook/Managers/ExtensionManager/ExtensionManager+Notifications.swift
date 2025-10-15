//
//  ExtensionManager+Notifications.swift
//  Nook
//
//  Chrome Notifications API Bridge for WKWebExtension support
//  Implements chrome.notifications.* APIs (Manifest v3)
//

import Foundation
import WebKit
import UserNotifications

// MARK: - Chrome Notifications API Bridge
@available(macOS 15.4, *)
extension ExtensionManager {
    
    // MARK: - Notification Types
    
    /// Represents a notification
    struct ChromeNotification {
        let id: String
        let extensionId: String
        let type: String // "basic", "image", "list", "progress"
        let iconUrl: String?
        let title: String
        let message: String
        let contextMessage: String?
        let priority: Int
        let eventTime: Date?
        let buttons: [[String: String]]?
        let imageUrl: String?
        let items: [[String: String]]?
        let progress: Int?
        let requireInteraction: Bool
        let silent: Bool
    }
    
    /// Storage for notifications
    private static var chromeNotifications: [String: ChromeNotification] = [:]
    private static var chromeNotificationsLock = NSLock()
    
    private var chromeNotificationsAccess: [String: ChromeNotification] {
        get {
            ExtensionManager.chromeNotificationsLock.lock()
            defer { ExtensionManager.chromeNotificationsLock.unlock() }
            return ExtensionManager.chromeNotifications
        }
        set {
            ExtensionManager.chromeNotificationsLock.lock()
            defer { ExtensionManager.chromeNotificationsLock.unlock() }
            ExtensionManager.chromeNotifications = newValue
        }
    }
    
    // MARK: - chrome.notifications.create
    
    func handleNotificationsCreate(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("📨 [ExtensionManager+Notifications] Handling notifications.create")
        
        guard let options = message["options"] as? [String: Any] else {
            print("❌ [ExtensionManager+Notifications] Missing options")
            replyHandler(["error": "Missing options"])
            return
        }
        
        let notificationId = message["notificationId"] as? String ?? UUID().uuidString
        
        createNotification(id: notificationId, options: options, extensionId: extensionId, replyHandler: replyHandler)
    }
    
    private func createNotification(id: String, options: [String: Any], extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("🔔 [ExtensionManager+Notifications] Creating notification: \(id)")
        
        // Extract notification properties
        let type = options["type"] as? String ?? "basic"
        let iconUrl = options["iconUrl"] as? String
        let title = options["title"] as? String ?? ""
        let message = options["message"] as? String ?? ""
        let contextMessage = options["contextMessage"] as? String
        let priority = options["priority"] as? Int ?? 0
        let buttons = options["buttons"] as? [[String: String]]
        let imageUrl = options["imageUrl"] as? String
        let items = options["items"] as? [[String: String]]
        let progress = options["progress"] as? Int
        let requireInteraction = options["requireInteraction"] as? Bool ?? false
        let silent = options["silent"] as? Bool ?? false
        
        let eventTime: Date?
        if let eventTimeMs = options["eventTime"] as? Double {
            eventTime = Date(timeIntervalSince1970: eventTimeMs / 1000.0)
        } else {
            eventTime = nil
        }
        
        // Create notification object
        let notification = ChromeNotification(
            id: id,
            extensionId: extensionId,
            type: type,
            iconUrl: iconUrl,
            title: title,
            message: message,
            contextMessage: contextMessage,
            priority: priority,
            eventTime: eventTime,
            buttons: buttons,
            imageUrl: imageUrl,
            items: items,
            progress: progress,
            requireInteraction: requireInteraction,
            silent: silent
        )
        
        // Store notification
        var notifications = chromeNotificationsAccess
        notifications[id] = notification
        chromeNotificationsAccess = notifications
        
        // Request notification permission if needed
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("❌ [ExtensionManager+Notifications] Permission error: \(error)")
                replyHandler(["error": error.localizedDescription])
                return
            }
            
            guard granted else {
                print("❌ [ExtensionManager+Notifications] Notification permission denied")
                replyHandler(["error": "Notification permission denied"])
                return
            }
            
            // Create and display the notification
            self.displayNotification(notification, replyHandler: replyHandler)
        }
    }
    
    private func displayNotification(_ notification: ChromeNotification, replyHandler: @escaping (Any?) -> Void) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.message
        
        if let contextMessage = notification.contextMessage {
            content.subtitle = contextMessage
        }
        
        if !notification.silent {
            content.sound = .default
        }
        
        // Add extension ID to user info for click handling
        content.userInfo = [
            "extensionId": notification.extensionId,
            "notificationId": notification.id,
            "type": "chromeNotification"
        ]
        
        // Add buttons as actions if present
        if let buttons = notification.buttons {
            var actions: [UNNotificationAction] = []
            for (index, button) in buttons.enumerated() {
                if let title = button["title"] {
                    let action = UNNotificationAction(
                        identifier: "button_\(index)",
                        title: title,
                        options: []
                    )
                    actions.append(action)
                }
            }
            
            if !actions.isEmpty {
                let category = UNNotificationCategory(
                    identifier: "chrome_notification_\(notification.id)",
                    actions: actions,
                    intentIdentifiers: [],
                    options: []
                )
                UNUserNotificationCenter.current().setNotificationCategories([category])
                content.categoryIdentifier = "chrome_notification_\(notification.id)"
            }
        }
        
        // Create trigger
        let trigger: UNNotificationTrigger?
        if notification.requireInteraction {
            // No trigger = persistent notification
            trigger = nil
        } else {
            // Auto-dismiss after a delay
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        }
        
        // Create request
        let request = UNNotificationRequest(
            identifier: notification.id,
            content: content,
            trigger: trigger
        )
        
        // Add notification
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("❌ [ExtensionManager+Notifications] Failed to display notification: \(error)")
                replyHandler(["error": error.localizedDescription])
            } else {
                print("✅ [ExtensionManager+Notifications] Notification displayed: \(notification.id)")
                replyHandler(["notificationId": notification.id])
            }
        }
    }
    
    // MARK: - chrome.notifications.update
    
    func handleNotificationsUpdate(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("📨 [ExtensionManager+Notifications] Handling notifications.update")
        
        guard let notificationId = message["notificationId"] as? String else {
            print("❌ [ExtensionManager+Notifications] Missing notificationId")
            replyHandler(["error": "Missing notificationId"])
            return
        }
        
        guard let options = message["options"] as? [String: Any] else {
            print("❌ [ExtensionManager+Notifications] Missing options")
            replyHandler(["error": "Missing options"])
            return
        }
        
        var notifications = chromeNotificationsAccess
        guard var notification = notifications[notificationId] else {
            print("❌ [ExtensionManager+Notifications] Notification not found: \(notificationId)")
            replyHandler(["wasUpdated": false])
            return
        }
        
        // Update notification properties
        let type = options["type"] as? String ?? notification.type
        let iconUrl = options["iconUrl"] as? String ?? notification.iconUrl
        let title = options["title"] as? String ?? notification.title
        let message = options["message"] as? String ?? notification.message
        let contextMessage = options["contextMessage"] as? String ?? notification.contextMessage
        let priority = options["priority"] as? Int ?? notification.priority
        let buttons = options["buttons"] as? [[String: String]] ?? notification.buttons
        let imageUrl = options["imageUrl"] as? String ?? notification.imageUrl
        let items = options["items"] as? [[String: String]] ?? notification.items
        let progress = options["progress"] as? Int ?? notification.progress
        let requireInteraction = options["requireInteraction"] as? Bool ?? notification.requireInteraction
        let silent = options["silent"] as? Bool ?? notification.silent
        
        let eventTime: Date?
        if let eventTimeMs = options["eventTime"] as? Double {
            eventTime = Date(timeIntervalSince1970: eventTimeMs / 1000.0)
        } else {
            eventTime = notification.eventTime
        }
        
        // Create updated notification
        let updatedNotification = ChromeNotification(
            id: notification.id,
            extensionId: notification.extensionId,
            type: type,
            iconUrl: iconUrl,
            title: title,
            message: message,
            contextMessage: contextMessage,
            priority: priority,
            eventTime: eventTime,
            buttons: buttons,
            imageUrl: imageUrl,
            items: items,
            progress: progress,
            requireInteraction: requireInteraction,
            silent: silent
        )
        
        notifications[notificationId] = updatedNotification
        chromeNotificationsAccess = notifications
        
        // Re-display the notification
        displayNotification(updatedNotification) { response in
            if let error = response as? [String: Any], error["error"] != nil {
                replyHandler(["wasUpdated": false])
            } else {
                replyHandler(["wasUpdated": true])
            }
        }
    }
    
    // MARK: - chrome.notifications.clear
    
    func handleNotificationsClear(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("📨 [ExtensionManager+Notifications] Handling notifications.clear")
        
        guard let notificationId = message["notificationId"] as? String else {
            print("❌ [ExtensionManager+Notifications] Missing notificationId")
            replyHandler(["error": "Missing notificationId"])
            return
        }
        
        var notifications = chromeNotificationsAccess
        let existed = notifications[notificationId] != nil
        notifications.removeValue(forKey: notificationId)
        chromeNotificationsAccess = notifications
        
        // Remove from notification center
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationId])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationId])
        
        print("✅ [ExtensionManager+Notifications] Notification cleared: \(notificationId)")
        replyHandler(["wasCleared": existed])
    }
    
    // MARK: - chrome.notifications.getAll
    
    func handleNotificationsGetAll(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("📨 [ExtensionManager+Notifications] Handling notifications.getAll")
        
        let notifications = chromeNotificationsAccess
        let extensionNotifications = notifications.filter { $0.value.extensionId == extensionId }
        
        var result: [String: [String: Any]] = [:]
        for (id, notification) in extensionNotifications {
            result[id] = notificationToDict(notification)
        }
        
        print("✅ [ExtensionManager+Notifications] Returning \(result.count) notifications")
        replyHandler(["notifications": result])
    }
    
    // MARK: - chrome.notifications.getPermissionLevel
    
    func handleNotificationsGetPermissionLevel(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("📨 [ExtensionManager+Notifications] Handling notifications.getPermissionLevel")
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let level: String
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                level = "granted"
            case .denied:
                level = "denied"
            case .notDetermined:
                level = "notDetermined"
            @unknown default:
                level = "denied"
            }
            
            print("✅ [ExtensionManager+Notifications] Permission level: \(level)")
            replyHandler(["level": level])
        }
    }
    
    // MARK: - Helper Methods
    
    private func notificationToDict(_ notification: ChromeNotification) -> [String: Any] {
        var dict: [String: Any] = [
            "type": notification.type,
            "title": notification.title,
            "message": notification.message,
            "priority": notification.priority,
            "requireInteraction": notification.requireInteraction,
            "silent": notification.silent
        ]
        
        if let iconUrl = notification.iconUrl {
            dict["iconUrl"] = iconUrl
        }
        if let contextMessage = notification.contextMessage {
            dict["contextMessage"] = contextMessage
        }
        if let eventTime = notification.eventTime {
            dict["eventTime"] = eventTime.timeIntervalSince1970 * 1000
        }
        if let buttons = notification.buttons {
            dict["buttons"] = buttons
        }
        if let imageUrl = notification.imageUrl {
            dict["imageUrl"] = imageUrl
        }
        if let items = notification.items {
            dict["items"] = items
        }
        if let progress = notification.progress {
            dict["progress"] = progress
        }
        
        return dict
    }
    
    // MARK: - Notification Event Handling
    
    func notifyExtensionOfNotificationClick(notificationId: String, extensionId: String, buttonIndex: Int? = nil) {
        print("🔔 [ExtensionManager+Notifications] Notifying extension of notification click: \(notificationId)")
        
        guard let context = getExtensionContext(for: extensionId) else {
            print("❌ [ExtensionManager+Notifications] No context found for extension: \(extensionId)")
            return
        }
        
        guard let webView = getBackgroundWebView(for: context) else {
            print("❌ [ExtensionManager+Notifications] No background page for extension: \(extensionId)")
            return
        }
        
        let buttonIndexValue = buttonIndex ?? -1
        let script = """
        (function() {
            if (window.chrome && window.chrome.notifications && window.chrome.notifications.onClicked) {
                window.chrome.notifications.onClicked._trigger('\(notificationId)');
            }
            if (\(buttonIndexValue) >= 0 && window.chrome && window.chrome.notifications && window.chrome.notifications.onButtonClicked) {
                window.chrome.notifications.onButtonClicked._trigger('\(notificationId)', \(buttonIndexValue));
            }
        })();
        """
        
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ [ExtensionManager+Notifications] Error notifying extension: \(error)")
            } else {
                print("✅ [ExtensionManager+Notifications] Extension notified of click")
            }
        }
    }
    
    func notifyExtensionOfNotificationClosed(notificationId: String, extensionId: String, byUser: Bool) {
        print("🔔 [ExtensionManager+Notifications] Notifying extension of notification closed: \(notificationId)")
        
        guard let context = getExtensionContext(for: extensionId) else {
            print("❌ [ExtensionManager+Notifications] No context found for extension: \(extensionId)")
            return
        }
        
        guard let webView = getBackgroundWebView(for: context) else {
            print("❌ [ExtensionManager+Notifications] No background page for extension: \(extensionId)")
            return
        }
        
        let script = """
        (function() {
            if (window.chrome && window.chrome.notifications && window.chrome.notifications.onClosed) {
                window.chrome.notifications.onClosed._trigger('\(notificationId)', \(byUser));
            }
        })();
        """
        
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ [ExtensionManager+Notifications] Error notifying extension: \(error)")
            } else {
                print("✅ [ExtensionManager+Notifications] Extension notified of closed")
            }
        }
    }
    
    // MARK: - Script Message Handler
    
    func handleNotificationsScriptMessage(_ message: WKScriptMessage) {
        print("📨 [ExtensionManager+Notifications] Received notifications script message")
        
        guard let body = message.body as? [String: Any] else {
            print("❌ [ExtensionManager+Notifications] Invalid message body")
            return
        }
        
        guard let extensionId = body["extensionId"] as? String else {
            print("❌ [ExtensionManager+Notifications] Missing extensionId")
            return
        }
        
        guard let method = body["method"] as? String else {
            print("❌ [ExtensionManager+Notifications] Missing method")
            return
        }
        
        let args = body["args"] as? [String: Any] ?? [:]
        let messageId = body["messageId"] as? String ?? UUID().uuidString
        
        // Route to appropriate handler
        let replyHandler: (Any?) -> Void = { [weak self] response in
            self?.sendNotificationsResponse(messageId: messageId, response: response, to: message.webView)
        }
        
        switch method {
        case "create":
            handleNotificationsCreate(args, from: extensionId, replyHandler: replyHandler)
        case "update":
            handleNotificationsUpdate(args, from: extensionId, replyHandler: replyHandler)
        case "clear":
            handleNotificationsClear(args, from: extensionId, replyHandler: replyHandler)
        case "getAll":
            handleNotificationsGetAll(args, from: extensionId, replyHandler: replyHandler)
        case "getPermissionLevel":
            handleNotificationsGetPermissionLevel(args, from: extensionId, replyHandler: replyHandler)
        default:
            print("❌ [ExtensionManager+Notifications] Unknown method: \(method)")
            replyHandler(["error": "Unknown method: \(method)"])
        }
    }
    
    private func sendNotificationsResponse(messageId: String, response: Any?, to webView: WKWebView?) {
        guard let webView = webView else {
            print("❌ [ExtensionManager+Notifications] No web view for response")
            return
        }
        
        let responseJson = jsonString(from: response ?? [:])
        let script = """
        (function() {
            if (window.__chromeNotificationsCallbacks && window.__chromeNotificationsCallbacks['\(messageId)']) {
                window.__chromeNotificationsCallbacks['\(messageId)'](\(responseJson));
                delete window.__chromeNotificationsCallbacks['\(messageId)'];
            }
        })();
        """
        
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ [ExtensionManager+Notifications] Error sending response: \(error)")
            }
        }
    }
    
    // MARK: - API Injection
    
    func injectNotificationsAPI(into webView: WKWebView, for extensionId: String) {
        print("💉 [ExtensionManager+Notifications] Injecting notifications API for extension: \(extensionId)")
        
        let script = generateNotificationsAPIScript(extensionId: extensionId)
        
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ [ExtensionManager+Notifications] Error injecting notifications API: \(error)")
            } else {
                print("✅ [ExtensionManager+Notifications] Notifications API injected")
            }
        }
    }
    
    func generateNotificationsAPIScript(extensionId: String) -> String {
        return """
        (function() {
            'use strict';
            
            console.log('🔔 [Notifications API] Initializing chrome.notifications for extension: \(extensionId)');
            
            if (!window.chrome) {
                window.chrome = {};
            }
            
            if (window.chrome.notifications) {
                console.log('⚠️ [Notifications API] chrome.notifications already exists, skipping initialization');
                return;
            }
            
            // Callback storage
            if (!window.__chromeNotificationsCallbacks) {
                window.__chromeNotificationsCallbacks = {};
            }
            
            // Message counter for unique IDs
            let messageCounter = 0;
            
            function sendNotificationsMessage(method, args, callback) {
                const messageId = 'notifications_' + (++messageCounter) + '_' + Date.now();
                
                // Store callback if provided
                if (callback) {
                    window.__chromeNotificationsCallbacks[messageId] = callback;
                }
                
                const message = {
                    extensionId: '\(extensionId)',
                    method: method,
                    args: args,
                    messageId: messageId
                };
                
                try {
                    window.webkit.messageHandlers.chromeNotifications.postMessage(message);
                } catch (error) {
                    console.error('[Notifications API] Error sending message:', error);
                    if (callback) {
                        callback({ error: error.message });
                        delete window.__chromeNotificationsCallbacks[messageId];
                    }
                }
                
                return new Promise((resolve, reject) => {
                    if (!callback) {
                        window.__chromeNotificationsCallbacks[messageId] = (response) => {
                            if (response && response.error) {
                                reject(new Error(response.error));
                            } else {
                                resolve(response);
                            }
                        };
                    }
                });
            }
            
            chrome.notifications = {
                create: function(notificationId, options, callback) {
                    if (typeof notificationId === 'object') {
                        // notificationId is optional, shift arguments
                        callback = options;
                        options = notificationId;
                        notificationId = undefined;
                    }
                    return sendNotificationsMessage('create', { notificationId: notificationId, options: options }, callback);
                },
                
                update: function(notificationId, options, callback) {
                    return sendNotificationsMessage('update', { notificationId: notificationId, options: options }, callback);
                },
                
                clear: function(notificationId, callback) {
                    return sendNotificationsMessage('clear', { notificationId: notificationId }, callback);
                },
                
                getAll: function(callback) {
                    return sendNotificationsMessage('getAll', {}, callback);
                },
                
                getPermissionLevel: function(callback) {
                    return sendNotificationsMessage('getPermissionLevel', {}, callback);
                },
                
                onClicked: {
                    _listeners: [],
                    addListener: function(callback) {
                        this._listeners.push(callback);
                        console.log('[Notifications API] onClicked listener added');
                    },
                    removeListener: function(callback) {
                        const index = this._listeners.indexOf(callback);
                        if (index > -1) {
                            this._listeners.splice(index, 1);
                        }
                    },
                    _trigger: function(notificationId) {
                        this._listeners.forEach(listener => {
                            try {
                                listener(notificationId);
                            } catch (error) {
                                console.error('[Notifications API] Error in onClicked listener:', error);
                            }
                        });
                    }
                },
                
                onButtonClicked: {
                    _listeners: [],
                    addListener: function(callback) {
                        this._listeners.push(callback);
                        console.log('[Notifications API] onButtonClicked listener added');
                    },
                    removeListener: function(callback) {
                        const index = this._listeners.indexOf(callback);
                        if (index > -1) {
                            this._listeners.splice(index, 1);
                        }
                    },
                    _trigger: function(notificationId, buttonIndex) {
                        this._listeners.forEach(listener => {
                            try {
                                listener(notificationId, buttonIndex);
                            } catch (error) {
                                console.error('[Notifications API] Error in onButtonClicked listener:', error);
                            }
                        });
                    }
                },
                
                onClosed: {
                    _listeners: [],
                    addListener: function(callback) {
                        this._listeners.push(callback);
                        console.log('[Notifications API] onClosed listener added');
                    },
                    removeListener: function(callback) {
                        const index = this._listeners.indexOf(callback);
                        if (index > -1) {
                            this._listeners.splice(index, 1);
                        }
                    },
                    _trigger: function(notificationId, byUser) {
                        this._listeners.forEach(listener => {
                            try {
                                listener(notificationId, byUser);
                            } catch (error) {
                                console.error('[Notifications API] Error in onClosed listener:', error);
                            }
                        });
                    }
                }
            };
            
            // Template types enum
            chrome.notifications.TemplateType = {
                BASIC: 'basic',
                IMAGE: 'image',
                LIST: 'list',
                PROGRESS: 'progress'
            };
            
            // Permission levels enum
            chrome.notifications.PermissionLevel = {
                GRANTED: 'granted',
                DENIED: 'denied'
            };
            
            console.log('✅ [Notifications API] chrome.notifications initialized successfully');
        })();
        """
    }
    
    private func jsonString(from object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

