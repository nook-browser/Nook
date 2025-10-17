//
//  ExtensionManager+ContextMenus.swift
//  Nook
//
//  Chrome Context Menus API Bridge for WKWebExtension support
//  Implements chrome.contextMenus.* APIs (Manifest v3)
//

import Foundation
import WebKit
import AppKit

// MARK: - Chrome Context Menus API Bridge
@available(macOS 15.4, *)
extension ExtensionManager {
    
    // MARK: - Context Menu Types
    
    /// Represents a context menu item
    struct ContextMenuItem {
        let id: String
        let extensionId: String
        let title: String?
        let type: String // "normal", "checkbox", "radio", "separator"
        let contexts: [String] // "page", "selection", "link", "image", etc.
        let parentId: String?
        let documentUrlPatterns: [String]?
        let targetUrlPatterns: [String]?
        let enabled: Bool
        let checked: Bool?
        let visible: Bool
        let onclick: String? // Callback function name
    }
    
    /// Storage for context menu items
    private static var contextMenuItems: [String: ContextMenuItem] = [:]
    private static var contextMenuItemsLock = NSLock()
    
    /// Radio group tracking for radio menu items
    private static var radioGroups: [String: [String]] = [:] // parentId -> [itemIds]
    
    private var contextMenuItemsAccess: [String: ContextMenuItem] {
        get {
            ExtensionManager.contextMenuItemsLock.lock()
            defer { ExtensionManager.contextMenuItemsLock.unlock() }
            return ExtensionManager.contextMenuItems
        }
        set {
            ExtensionManager.contextMenuItemsLock.lock()
            defer { ExtensionManager.contextMenuItemsLock.unlock() }
            ExtensionManager.contextMenuItems = newValue
        }
    }
    
    // MARK: - chrome.contextMenus.create
    
    func handleContextMenusCreate(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("🍔 [ExtensionManager+ContextMenus] create called")
        
        guard let id = message["id"] as? String else {
            // If no ID provided, generate one
            let generatedId = "\(extensionId)_\(UUID().uuidString)"
            createContextMenuItem(id: generatedId, properties: message, extensionId: extensionId, replyHandler: replyHandler)
            return
        }
        
        createContextMenuItem(id: id, properties: message, extensionId: extensionId, replyHandler: replyHandler)
    }
    
    private func createContextMenuItem(id: String, properties: [String: Any], extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        let title = properties["title"] as? String
        let type = properties["type"] as? String ?? "normal"
        let contexts = properties["contexts"] as? [String] ?? ["page"]
        let parentId = properties["parentId"] as? String
        let documentUrlPatterns = properties["documentUrlPatterns"] as? [String]
        let targetUrlPatterns = properties["targetUrlPatterns"] as? [String]
        let enabled = properties["enabled"] as? Bool ?? true
        let checked = properties["checked"] as? Bool
        let visible = properties["visible"] as? Bool ?? true
        let onclick = properties["onclick"] as? String
        
        let menuItem = ContextMenuItem(
            id: id,
            extensionId: extensionId,
            title: title,
            type: type,
            contexts: contexts,
            parentId: parentId,
            documentUrlPatterns: documentUrlPatterns,
            targetUrlPatterns: targetUrlPatterns,
            enabled: enabled,
            checked: checked,
            visible: visible,
            onclick: onclick
        )
        
        ExtensionManager.contextMenuItemsLock.lock()
        ExtensionManager.contextMenuItems[id] = menuItem
        
        // Track radio groups
        if type == "radio", let parentId = parentId {
            if ExtensionManager.radioGroups[parentId] == nil {
                ExtensionManager.radioGroups[parentId] = []
            }
            ExtensionManager.radioGroups[parentId]?.append(id)
        }
        ExtensionManager.contextMenuItemsLock.unlock()
        
        print("✅ [ExtensionManager+ContextMenus] Created menu item: '\(title ?? id)' (ID: \(id))")
        replyHandler(["id": id])
    }
    
    // MARK: - chrome.contextMenus.update
    
    func handleContextMenusUpdate(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("🔄 [ExtensionManager+ContextMenus] update called")
        
        guard let id = message["id"] as? String else {
            print("❌ [ExtensionManager+ContextMenus] Missing 'id' parameter")
            replyHandler(["error": "Missing 'id' parameter"])
            return
        }
        
        ExtensionManager.contextMenuItemsLock.lock()
        guard var menuItem = ExtensionManager.contextMenuItems[id] else {
            ExtensionManager.contextMenuItemsLock.unlock()
            print("❌ [ExtensionManager+ContextMenus] Menu item not found: \(id)")
            replyHandler(["error": "Menu item not found"])
            return
        }
        
        // Update properties
        let properties = message["properties"] as? [String: Any] ?? [:]
        
        let updatedItem = ContextMenuItem(
            id: menuItem.id,
            extensionId: menuItem.extensionId,
            title: properties["title"] as? String ?? menuItem.title,
            type: properties["type"] as? String ?? menuItem.type,
            contexts: properties["contexts"] as? [String] ?? menuItem.contexts,
            parentId: properties["parentId"] as? String ?? menuItem.parentId,
            documentUrlPatterns: properties["documentUrlPatterns"] as? [String] ?? menuItem.documentUrlPatterns,
            targetUrlPatterns: properties["targetUrlPatterns"] as? [String] ?? menuItem.targetUrlPatterns,
            enabled: properties["enabled"] as? Bool ?? menuItem.enabled,
            checked: properties["checked"] as? Bool ?? menuItem.checked,
            visible: properties["visible"] as? Bool ?? menuItem.visible,
            onclick: properties["onclick"] as? String ?? menuItem.onclick
        )
        
        ExtensionManager.contextMenuItems[id] = updatedItem
        ExtensionManager.contextMenuItemsLock.unlock()
        
        print("✅ [ExtensionManager+ContextMenus] Updated menu item: \(id)")
        replyHandler(["success": true])
    }
    
    // MARK: - chrome.contextMenus.remove
    
    func handleContextMenusRemove(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("🗑️ [ExtensionManager+ContextMenus] remove called")
        
        guard let id = message["id"] as? String else {
            print("❌ [ExtensionManager+ContextMenus] Missing 'id' parameter")
            replyHandler(["error": "Missing 'id' parameter"])
            return
        }
        
        ExtensionManager.contextMenuItemsLock.lock()
        
        // Remove from items
        guard ExtensionManager.contextMenuItems.removeValue(forKey: id) != nil else {
            ExtensionManager.contextMenuItemsLock.unlock()
            print("❌ [ExtensionManager+ContextMenus] Menu item not found: \(id)")
            replyHandler(["error": "Menu item not found"])
            return
        }
        
        // Clean up radio groups
        for (parentId, var items) in ExtensionManager.radioGroups {
            if let index = items.firstIndex(of: id) {
                items.remove(at: index)
                ExtensionManager.radioGroups[parentId] = items
            }
        }
        
        ExtensionManager.contextMenuItemsLock.unlock()
        
        print("✅ [ExtensionManager+ContextMenus] Removed menu item: \(id)")
        replyHandler(["success": true])
    }
    
    // MARK: - chrome.contextMenus.removeAll
    
    func handleContextMenusRemoveAll(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("🗑️ [ExtensionManager+ContextMenus] removeAll called")
        
        ExtensionManager.contextMenuItemsLock.lock()
        
        // Remove all items for this extension
        let itemsToRemove = ExtensionManager.contextMenuItems.filter { $0.value.extensionId == extensionId }
        for (id, _) in itemsToRemove {
            ExtensionManager.contextMenuItems.removeValue(forKey: id)
        }
        
        // Clean up radio groups for this extension
        ExtensionManager.radioGroups = ExtensionManager.radioGroups.filter { (parentId, _) in
            !parentId.starts(with: extensionId)
        }
        
        ExtensionManager.contextMenuItemsLock.unlock()
        
        print("✅ [ExtensionManager+ContextMenus] Removed all menu items for extension: \(extensionId)")
        replyHandler(["success": true])
    }
    
    // MARK: - Context Menu Display
    
    /// Get context menu items for a given context
    func getContextMenuItems(for extensionId: String, context: String, info: [String: Any]? = nil) -> [ContextMenuItem] {
        ExtensionManager.contextMenuItemsLock.lock()
        defer { ExtensionManager.contextMenuItemsLock.unlock() }
        
        let items = ExtensionManager.contextMenuItems.values.filter { item in
            guard item.extensionId == extensionId else { return false }
            guard item.visible else { return false }
            guard item.contexts.contains(context) || item.contexts.contains("all") else { return false }
            
            // TODO: Check URL patterns if provided
            // if let documentUrlPatterns = item.documentUrlPatterns { ... }
            // if let targetUrlPatterns = item.targetUrlPatterns { ... }
            
            return true
        }
        
        return Array(items).sorted { ($0.parentId ?? "") < ($1.parentId ?? "") }
    }
    
    /// Build NSMenu from context menu items
    func buildContextMenu(for extensionId: String, context: String, info: [String: Any]? = nil) -> NSMenu? {
        let items = getContextMenuItems(for: extensionId, context: context, info: info)
        
        guard !items.isEmpty else {
            return nil
        }
        
        let menu = NSMenu()
        
        // Build menu hierarchy
        var menuItemMap: [String: NSMenuItem] = [:]
        
        // First pass: create root items
        for item in items where item.parentId == nil {
            let nsMenuItem = createNSMenuItem(from: item, extensionId: extensionId, info: info)
            menu.addItem(nsMenuItem)
            menuItemMap[item.id] = nsMenuItem
        }
        
        // Second pass: add child items
        for item in items where item.parentId != nil {
            if let parentMenuItem = menuItemMap[item.parentId!] {
                if parentMenuItem.submenu == nil {
                    parentMenuItem.submenu = NSMenu()
                }
                let nsMenuItem = createNSMenuItem(from: item, extensionId: extensionId, info: info)
                parentMenuItem.submenu?.addItem(nsMenuItem)
                menuItemMap[item.id] = nsMenuItem
            }
        }
        
        return menu
    }
    
    private func createNSMenuItem(from item: ContextMenuItem, extensionId: String, info: [String: Any]?) -> NSMenuItem {
        let nsMenuItem: NSMenuItem
        
        switch item.type {
        case "separator":
            nsMenuItem = NSMenuItem.separator()
            
        case "checkbox":
            nsMenuItem = NSMenuItem(
                title: item.title ?? "",
                action: #selector(handleContextMenuClick(_:)),
                keyEquivalent: ""
            )
            nsMenuItem.state = item.checked == true ? .on : .off
            nsMenuItem.representedObject = ["itemId": item.id, "extensionId": extensionId, "info": info ?? [:]]
            nsMenuItem.target = self
            nsMenuItem.isEnabled = item.enabled
            
        case "radio":
            nsMenuItem = NSMenuItem(
                title: item.title ?? "",
                action: #selector(handleContextMenuClick(_:)),
                keyEquivalent: ""
            )
            nsMenuItem.state = item.checked == true ? .on : .off
            nsMenuItem.representedObject = ["itemId": item.id, "extensionId": extensionId, "info": info ?? [:]]
            nsMenuItem.target = self
            nsMenuItem.isEnabled = item.enabled
            
        default: // "normal"
            nsMenuItem = NSMenuItem(
                title: item.title ?? "",
                action: #selector(handleContextMenuClick(_:)),
                keyEquivalent: ""
            )
            nsMenuItem.representedObject = ["itemId": item.id, "extensionId": extensionId, "info": info ?? [:]]
            nsMenuItem.target = self
            nsMenuItem.isEnabled = item.enabled
        }
        
        return nsMenuItem
    }
    
    @objc private func handleContextMenuClick(_ sender: NSMenuItem) {
        guard let data = sender.representedObject as? [String: Any],
              let itemId = data["itemId"] as? String,
              let extensionId = data["extensionId"] as? String,
              let info = data["info"] as? [String: Any] else {
            print("❌ [ExtensionManager+ContextMenus] Invalid menu item data")
            return
        }
        
        print("🍔 [ExtensionManager+ContextMenus] Menu item clicked: \(itemId)")
        
        // Update checked state for checkbox/radio items
        ExtensionManager.contextMenuItemsLock.lock()
        if let menuItem = ExtensionManager.contextMenuItems[itemId] {
            if menuItem.type == "checkbox" {
                let newChecked = !(menuItem.checked ?? false)
                let updatedItem = ContextMenuItem(
                    id: menuItem.id,
                    extensionId: menuItem.extensionId,
                    title: menuItem.title,
                    type: menuItem.type,
                    contexts: menuItem.contexts,
                    parentId: menuItem.parentId,
                    documentUrlPatterns: menuItem.documentUrlPatterns,
                    targetUrlPatterns: menuItem.targetUrlPatterns,
                    enabled: menuItem.enabled,
                    checked: newChecked,
                    visible: menuItem.visible,
                    onclick: menuItem.onclick
                )
                ExtensionManager.contextMenuItems[itemId] = updatedItem
            } else if menuItem.type == "radio" {
                // Uncheck all other radio items in the same group
                if let parentId = menuItem.parentId,
                   let groupItems = ExtensionManager.radioGroups[parentId] {
                    for radioId in groupItems where radioId != itemId {
                        if var radioItem = ExtensionManager.contextMenuItems[radioId] {
                            let updatedRadioItem = ContextMenuItem(
                                id: radioItem.id,
                                extensionId: radioItem.extensionId,
                                title: radioItem.title,
                                type: radioItem.type,
                                contexts: radioItem.contexts,
                                parentId: radioItem.parentId,
                                documentUrlPatterns: radioItem.documentUrlPatterns,
                                targetUrlPatterns: radioItem.targetUrlPatterns,
                                enabled: radioItem.enabled,
                                checked: false,
                                visible: radioItem.visible,
                                onclick: radioItem.onclick
                            )
                            ExtensionManager.contextMenuItems[radioId] = updatedRadioItem
                        }
                    }
                }
                
                // Check this item
                let updatedItem = ContextMenuItem(
                    id: menuItem.id,
                    extensionId: menuItem.extensionId,
                    title: menuItem.title,
                    type: menuItem.type,
                    contexts: menuItem.contexts,
                    parentId: menuItem.parentId,
                    documentUrlPatterns: menuItem.documentUrlPatterns,
                    targetUrlPatterns: menuItem.targetUrlPatterns,
                    enabled: menuItem.enabled,
                    checked: true,
                    visible: menuItem.visible,
                    onclick: menuItem.onclick
                )
                ExtensionManager.contextMenuItems[itemId] = updatedItem
            }
        }
        ExtensionManager.contextMenuItemsLock.unlock()
        
        // Notify extension about the click
        notifyExtensionOfMenuClick(itemId: itemId, extensionId: extensionId, info: info)
    }
    
    private func notifyExtensionOfMenuClick(itemId: String, extensionId: String, info: [String: Any]) {
        guard let extensionContext = extensionContextsAccess[extensionId] else {
            print("❌ [ExtensionManager+ContextMenus] Extension context not found: \(extensionId)")
            return
        }
        
        // Get the menu item to access checked state
        ExtensionManager.contextMenuItemsLock.lock()
        let menuItem = ExtensionManager.contextMenuItems[itemId]
        ExtensionManager.contextMenuItemsLock.unlock()
        
        // Prepare click info
        var clickInfo = info
        clickInfo["menuItemId"] = itemId
        if let checked = menuItem?.checked {
            clickInfo["checked"] = checked
        }
        
        // Get current tab info
        let tabInfo = getCurrentTabInfoForContextMenus()
        
        // Use MessagePort to send context menu click event to background service worker
        var eventData: [String: Any] = clickInfo
        if let tab = tabInfo {
            eventData["tab"] = tab
        }
        
        sendEventToBackground(eventType: "contextMenus.onClicked",
                            eventData: eventData,
                            for: extensionContext) { response, error in
            if let error = error {
                print("❌ [ExtensionManager+ContextMenus] Error sending menu click via MessagePort: \(error.localizedDescription)")
            } else {
                print("✅ [ExtensionManager+ContextMenus] Context menu click event sent to background via MessagePort")
            }
        }
    }
    
    // Helper function for getting current tab info
    private func getCurrentTabInfoForContextMenus() -> [String: Any]? {
        guard let browserManager = browserManagerAccess,
              let currentTab = browserManager.currentTabForActiveWindow() else {
            return nil
        }
        
        return [
            "id": currentTab.id.uuidString,
            "url": currentTab.url.absoluteString,
            "title": currentTab.name,
            "active": true,
            "windowId": 1 // Simplified window ID
        ]
    }
    
    // MARK: - Script Message Handler
    
    func handleContextMenusScriptMessage(_ message: WKScriptMessage) {
        print("📨 [ExtensionManager+ContextMenus] Received context menus script message")
        
        guard let body = message.body as? [String: Any] else {
            print("❌ [ExtensionManager+ContextMenus] Invalid message body")
            return
        }
        
        guard let extensionId = body["extensionId"] as? String else {
            print("❌ [ExtensionManager+ContextMenus] Missing extensionId")
            return
        }
        
        guard let method = body["method"] as? String else {
            print("❌ [ExtensionManager+ContextMenus] Missing method")
            return
        }
        
        let args = body["args"] as? [String: Any] ?? [:]
        let messageId = body["messageId"] as? String ?? UUID().uuidString
        
        // Route to appropriate handler
        let replyHandler: (Any?) -> Void = { [weak self] response in
            self?.sendContextMenusResponse(messageId: messageId, response: response, to: message.webView)
        }
        
        switch method {
        case "create":
            handleContextMenusCreate(args, from: extensionId, replyHandler: replyHandler)
        case "update":
            handleContextMenusUpdate(args, from: extensionId, replyHandler: replyHandler)
        case "remove":
            handleContextMenusRemove(args, from: extensionId, replyHandler: replyHandler)
        case "removeAll":
            handleContextMenusRemoveAll(args, from: extensionId, replyHandler: replyHandler)
        default:
            print("❌ [ExtensionManager+ContextMenus] Unknown method: \(method)")
            replyHandler(["error": "Unknown method: \(method)"])
        }
    }
    
    private func sendContextMenusResponse(messageId: String, response: Any?, to webView: WKWebView?) {
        guard let webView = webView else {
            print("❌ [ExtensionManager+ContextMenus] WebView not available for response")
            return
        }
        
        let responseData: [String: Any] = [
            "messageId": messageId,
            "response": response ?? NSNull()
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: responseData)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            let script = "window.__nookContextMenusResponse && window.__nookContextMenusResponse(\(jsonString));"
            
            webView.evaluateJavaScript(script) { _, error in
                if let error = error {
                    print("❌ [ExtensionManager+ContextMenus] Failed to send response: \(error)")
                }
            }
        } catch {
            print("❌ [ExtensionManager+ContextMenus] Failed to serialize response: \(error)")
        }
    }
    
    // MARK: - JavaScript Injection
    
    func injectContextMenusAPI(into webView: WKWebView, for extensionId: String) {
        let script = generateContextMenusAPIScript(extensionId: extensionId)
        
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ [ExtensionManager+ContextMenus] Error injecting context menus API: \(error)")
            } else {
                print("✅ [ExtensionManager+ContextMenus] Context menus API injected successfully for \(extensionId)")
            }
        }
    }
    
    func generateContextMenusAPIScript(extensionId: String) -> String {
        return """
        (function() {
            'use strict';
            
            console.log('🍔 [ContextMenus API] Initializing chrome.contextMenus for extension: \(extensionId)');
            
            if (typeof chrome === 'undefined') {
                window.chrome = {};
            }
            
            if (!chrome.contextMenus) {
                let messageIdCounter = 0;
                const pendingCallbacks = new Map();
                
                // Response handler
                window.__nookContextMenusResponse = function(data) {
                    const { messageId, response } = data;
                    const callback = pendingCallbacks.get(messageId);
                    if (callback) {
                        callback(response);
                        pendingCallbacks.delete(messageId);
                    }
                };
                
                function sendContextMenusMessage(method, args = {}, callback) {
                    const messageId = `contextMenus_${++messageIdCounter}_${Date.now()}`;
                    
                    if (callback) {
                        pendingCallbacks.set(messageId, callback);
                        
                        setTimeout(() => {
                            if (pendingCallbacks.has(messageId)) {
                                console.warn(`[ContextMenus API] Timeout for ${method}`);
                                pendingCallbacks.delete(messageId);
                            }
                        }, 5000);
                    }
                    
                    const message = {
                        extensionId: '\(extensionId)',
                        method: method,
                        args: args,
                        messageId: messageId
                    };
                    
                    try {
                        window.webkit.messageHandlers.chromeContextMenus.postMessage(message);
                    } catch (error) {
                        console.error('[ContextMenus API] Failed to send message:', error);
                        if (callback) {
                            callback({ error: error.message });
                            pendingCallbacks.delete(messageId);
                        }
                    }
                    
                    return new Promise((resolve, reject) => {
                        if (!callback) {
                            pendingCallbacks.set(messageId, (response) => {
                                if (response && response.error) {
                                    reject(new Error(response.error));
                                } else {
                                    resolve(response);
                                }
                            });
                        }
                    });
                }
                
                chrome.contextMenus = {
                    create: function(createProperties, callback) {
                        return sendContextMenusMessage('create', createProperties, callback);
                    },
                    
                    update: function(id, updateProperties, callback) {
                        return sendContextMenusMessage('update', { id: id, properties: updateProperties }, callback);
                    },
                    
                    remove: function(menuItemId, callback) {
                        return sendContextMenusMessage('remove', { id: menuItemId }, callback);
                    },
                    
                    removeAll: function(callback) {
                        return sendContextMenusMessage('removeAll', {}, callback);
                    },
                    
                    onClicked: {
                        _listeners: [],
                        addListener: function(callback) {
                            this._listeners.push(callback);
                            console.log('[ContextMenus API] onClicked listener added');
                        },
                        removeListener: function(callback) {
                            const index = this._listeners.indexOf(callback);
                            if (index > -1) {
                                this._listeners.splice(index, 1);
                            }
                        }
                    }
                };
                
                // Context types enum
                chrome.contextMenus.ContextType = {
                    ALL: 'all',
                    PAGE: 'page',
                    FRAME: 'frame',
                    SELECTION: 'selection',
                    LINK: 'link',
                    EDITABLE: 'editable',
                    IMAGE: 'image',
                    VIDEO: 'video',
                    AUDIO: 'audio'
                };
                
                // Item types enum
                chrome.contextMenus.ItemType = {
                    NORMAL: 'normal',
                    CHECKBOX: 'checkbox',
                    RADIO: 'radio',
                    SEPARATOR: 'separator'
                };
                
                console.log('✅ [ContextMenus API] chrome.contextMenus initialized');
                console.log('   🍔 Menu methods: create, update, remove, removeAll');
                console.log('   📋 Event: onClicked');
            }
        })();
        """
    }
    
    // MARK: - Helper Methods
    
    private func jsonString(from object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
    
    func getBackgroundWebView(for context: WKWebExtensionContext) -> WKWebView? {
        // TODO: Implement proper background webview retrieval
        // For now, return nil - this will need to be connected to the actual background page
        return nil
    }
}
