//
//  ExtensionManager+Commands.swift
//  Nook
//
//  Chrome Commands API Bridge for WKWebExtension support
//  Implements chrome.commands.* APIs (Manifest v3)
//

import Foundation
import WebKit
import Carbon.HIToolbox

// MARK: - Chrome Commands API Bridge
@available(macOS 15.4, *)
extension ExtensionManager {
    
    // MARK: - Command Types
    
    /// Represents a keyboard command
    struct ChromeCommand {
        let name: String
        let description: String?
        let shortcut: String?
        let global: Bool
        let extensionId: String
    }
    
    /// Storage for registered commands
    private static var chromeCommands: [String: [String: ChromeCommand]] = [:] // [extensionId: [commandName: command]]
    private static var chromeCommandsLock = NSLock()
    
    /// Storage for global keyboard event monitors
    private static var commandEventMonitors: [String: Any] = [:]
    private static var commandEventMonitorsLock = NSLock()
    
    private var chromeCommandsAccess: [String: [String: ChromeCommand]] {
        get {
            ExtensionManager.chromeCommandsLock.lock()
            defer { ExtensionManager.chromeCommandsLock.unlock() }
            return ExtensionManager.chromeCommands
        }
        set {
            ExtensionManager.chromeCommandsLock.lock()
            defer { ExtensionManager.chromeCommandsLock.unlock() }
            ExtensionManager.chromeCommands = newValue
        }
    }
    
    private var commandEventMonitorsAccess: [String: Any] {
        get {
            ExtensionManager.commandEventMonitorsLock.lock()
            defer { ExtensionManager.commandEventMonitorsLock.unlock() }
            return ExtensionManager.commandEventMonitors
        }
        set {
            ExtensionManager.commandEventMonitorsLock.lock()
            defer { ExtensionManager.commandEventMonitorsLock.unlock() }
            ExtensionManager.commandEventMonitors = newValue
        }
    }
    
    // MARK: - chrome.commands.getAll
    
    func handleCommandsGetAll(_ message: [String: Any], from extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        print("📨 [ExtensionManager+Commands] Handling commands.getAll for extension: \(extensionId)")
        
        // Get commands from manifest
        guard let context = getExtensionContext(for: extensionId) else {
            print("❌ [ExtensionManager+Commands] No context found for extension: \(extensionId)")
            replyHandler(["error": "Extension context not found"])
            return
        }
        
        // Parse commands from manifest
        let commands = parseCommandsFromManifest(context: context, extensionId: extensionId)
        
        // Convert to array of command objects
        let commandsArray = commands.values.map { command -> [String: Any] in
            var dict: [String: Any] = [
                "name": command.name
            ]
            
            if let description = command.description {
                dict["description"] = description
            }
            
            if let shortcut = command.shortcut {
                dict["shortcut"] = shortcut
            }
            
            return dict
        }
        
        print("✅ [ExtensionManager+Commands] Returning \(commandsArray.count) commands")
        replyHandler(["commands": commandsArray])
    }
    
    // MARK: - Command Registration
    
    func registerCommandsForExtension(_ extensionId: String) {
        print("⌨️ [ExtensionManager+Commands] Registering commands for extension: \(extensionId)")
        
        guard let context = getExtensionContext(for: extensionId) else {
            print("❌ [ExtensionManager+Commands] No context found for extension: \(extensionId)")
            return
        }
        
        // Parse and register commands
        let commands = parseCommandsFromManifest(context: context, extensionId: extensionId)
        
        // Store commands
        var allCommands = chromeCommandsAccess
        allCommands[extensionId] = commands
        chromeCommandsAccess = allCommands
        
        // Register keyboard shortcuts
        for (_, command) in commands {
            if let shortcut = command.shortcut {
                registerKeyboardShortcut(command: command, shortcut: shortcut)
            }
        }
        
        print("✅ [ExtensionManager+Commands] Registered \(commands.count) commands")
    }
    
    func unregisterCommandsForExtension(_ extensionId: String) {
        print("⌨️ [ExtensionManager+Commands] Unregistering commands for extension: \(extensionId)")
        
        // Remove commands
        var allCommands = chromeCommandsAccess
        if let commands = allCommands[extensionId] {
            // Unregister keyboard shortcuts
            for (_, command) in commands {
                unregisterKeyboardShortcut(command: command)
            }
            allCommands.removeValue(forKey: extensionId)
            chromeCommandsAccess = allCommands
        }
        
        print("✅ [ExtensionManager+Commands] Unregistered commands")
    }
    
    // MARK: - Manifest Parsing
    
    private func parseCommandsFromManifest(context: WKWebExtensionContext, extensionId: String) -> [String: ChromeCommand] {
        var commands: [String: ChromeCommand] = [:]
        
        // Try to get manifest dictionary
        guard let manifestData = context.webExtension.manifest as? [String: Any],
              let commandsDict = manifestData["commands"] as? [String: [String: Any]] else {
            print("ℹ️ [ExtensionManager+Commands] No commands found in manifest")
            return commands
        }
        
        // Parse each command
        for (commandName, commandData) in commandsDict {
            let description = commandData["description"] as? String
            let shortcut = commandData["suggested_key"] as? String ?? (commandData["suggested_key"] as? [String: Any])?["default"] as? String
            let global = commandData["global"] as? Bool ?? false
            
            let command = ChromeCommand(
                name: commandName,
                description: description,
                shortcut: shortcut,
                global: global,
                extensionId: extensionId
            )
            
            commands[commandName] = command
        }
        
        // Add default _execute_action command if not present
        if commands["_execute_action"] == nil {
            let defaultCommand = ChromeCommand(
                name: "_execute_action",
                description: "Activate the extension",
                shortcut: nil,
                global: false,
                extensionId: extensionId
            )
            commands["_execute_action"] = defaultCommand
        }
        
        return commands
    }
    
    // MARK: - Keyboard Shortcut Registration
    
    private func registerKeyboardShortcut(command: ChromeCommand, shortcut: String) {
        print("⌨️ [ExtensionManager+Commands] Registering shortcut '\(shortcut)' for command '\(command.name)'")
        
        // Parse shortcut string (e.g., "Ctrl+Shift+K" or "Command+B")
        let (modifiers, keyCode) = parseShortcut(shortcut)
        
        guard let keyCode = keyCode else {
            print("❌ [ExtensionManager+Commands] Failed to parse shortcut: \(shortcut)")
            return
        }
        
        // Create event monitor
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            
            // Check if modifiers match
            let eventModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if eventModifiers == modifiers && event.keyCode == keyCode {
                print("⌨️ [ExtensionManager+Commands] Shortcut triggered: \(shortcut)")
                self.triggerCommand(command: command)
                return nil // Consume event
            }
            
            return event
        }
        
        // Store monitor
        let monitorKey = "\(command.extensionId)_\(command.name)"
        var monitors = commandEventMonitorsAccess
        monitors[monitorKey] = monitor
        commandEventMonitorsAccess = monitors
        
        print("✅ [ExtensionManager+Commands] Keyboard shortcut registered")
    }
    
    private func unregisterKeyboardShortcut(command: ChromeCommand) {
        let monitorKey = "\(command.extensionId)_\(command.name)"
        
        var monitors = commandEventMonitorsAccess
        if let monitor = monitors[monitorKey] as? Any {
            NSEvent.removeMonitor(monitor)
            monitors.removeValue(forKey: monitorKey)
            commandEventMonitorsAccess = monitors
            print("✅ [ExtensionManager+Commands] Keyboard shortcut unregistered: \(command.name)")
        }
    }
    
    // MARK: - Shortcut Parsing
    
    private func parseShortcut(_ shortcut: String) -> (NSEvent.ModifierFlags, UInt16?) {
        let parts = shortcut.split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        
        var modifiers: NSEvent.ModifierFlags = []
        var keyString: String?
        
        for part in parts {
            let lowercasePart = part.lowercased()
            
            switch lowercasePart {
            case "ctrl", "control":
                modifiers.insert(.control)
            case "shift":
                modifiers.insert(.shift)
            case "alt", "option":
                modifiers.insert(.option)
            case "cmd", "command", "meta":
                modifiers.insert(.command)
            default:
                keyString = part
            }
        }
        
        guard let keyString = keyString else {
            return (modifiers, nil)
        }
        
        // Map key string to key code
        let keyCode = keyStringToKeyCode(keyString)
        
        return (modifiers, keyCode)
    }
    
    private func keyStringToKeyCode(_ keyString: String) -> UInt16? {
        let lowercaseKey = keyString.lowercased()
        
        // Common key mappings
        let keyMap: [String: UInt16] = [
            "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
            "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31,
            "p": 35, "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9,
            "w": 13, "x": 7, "y": 16, "z": 6,
            "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
            "6": 22, "7": 26, "8": 28, "9": 25,
            "space": 49, "return": 36, "enter": 36, "tab": 48, "escape": 53,
            "delete": 51, "backspace": 51,
            "up": 126, "down": 125, "left": 123, "right": 124,
            "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
            "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
            ",": 43, ".": 47, "/": 44, ";": 41, "'": 39, "[": 33, "]": 30,
            "\\": 42, "-": 27, "=": 24, "`": 50
        ]
        
        return keyMap[lowercaseKey]
    }
    
    // MARK: - Command Triggering
    
    private func triggerCommand(command: ChromeCommand) {
        print("🔥 [ExtensionManager+Commands] Triggering command: \(command.name) for extension: \(command.extensionId)")
        
        // Handle special commands
        if command.name == "_execute_action" {
            // Trigger the action (click the toolbar icon)
            handleActionClick(extensionId: command.extensionId)
            return
        }
        
        // Notify extension of command
        notifyExtensionOfCommand(command: command)
    }
    
    private func handleActionClick(extensionId: String) {
        print("🖱️ [ExtensionManager+Commands] Simulating action click for extension: \(extensionId)")
        
        guard let context = getExtensionContext(for: extensionId) else {
            print("❌ [ExtensionManager+Commands] No context found for extension: \(extensionId)")
            return
        }
        
        // Use MessagePort to send action click event to background service worker
        let tabInfo = getCurrentTabInfo() ?? [:]
        let eventData: [String: Any] = [
            "tab": tabInfo
        ]
        
        sendEventToBackground(eventType: "action.onClicked", 
                            eventData: eventData, 
                            for: context) { response, error in
            if let error = error {
                print("❌ [ExtensionManager+Commands] Error triggering action via MessagePort: \(error.localizedDescription)")
            } else {
                print("✅ [ExtensionManager+Commands] Action click event sent to background via MessagePort")
            }
        }
    }
    
    private func notifyExtensionOfCommand(command: ChromeCommand) {
        print("📢 [ExtensionManager+Commands] Notifying extension of command: \(command.name)")
        
        guard let context = getExtensionContext(for: command.extensionId) else {
            print("❌ [ExtensionManager+Commands] No context found for extension: \(command.extensionId)")
            return
        }
        
        // Use MessagePort to send command event to background service worker
        let eventData: [String: Any] = [
            "command": command.name,
            "shortcut": command.shortcut ?? ""
        ]
        
        sendEventToBackground(eventType: "commands.onCommand",
                            eventData: eventData,
                            for: context) { response, error in
            if let error = error {
                print("❌ [ExtensionManager+Commands] Error sending command via MessagePort: \(error.localizedDescription)")
            } else {
                print("✅ [ExtensionManager+Commands] Command '\(command.name)' sent to background via MessagePort")
            }
        }
    }
    
    // Helper function for getting current tab info (if not already defined)
    private func getCurrentTabInfo() -> [String: Any]? {
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
    
    // DEPRECATED: WebView approach - replaced by MessagePort system
    private func notifyExtensionOfCommand_DEPRECATED(command: ChromeCommand) {
        print("⚠️ [ExtensionManager+Commands] DEPRECATED: Using old WebView injection method")
        
        guard let context = getExtensionContext(for: command.extensionId) else {
            print("❌ [ExtensionManager+Commands] No context found for extension: \(command.extensionId)")
            return
        }
        
        guard let webView = getBackgroundWebView(for: context) else {
            print("❌ [ExtensionManager+Commands] No background page for extension: \(command.extensionId)")
            return
        }
        
        let script = """
        (function() {
            if (window.chrome && window.chrome.commands && window.chrome.commands.onCommand) {
                window.chrome.commands.onCommand._trigger('\(command.name)');
            }
        })();
        """
        
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ [ExtensionManager+Commands] Error notifying extension: \(error)")
            } else {
                print("✅ [ExtensionManager+Commands] Extension notified")
            }
        }
    }
    
    // MARK: - Script Message Handler
    
    func handleCommandsScriptMessage(_ message: WKScriptMessage) {
        print("📨 [ExtensionManager+Commands] Received commands script message")
        
        guard let body = message.body as? [String: Any] else {
            print("❌ [ExtensionManager+Commands] Invalid message body")
            return
        }
        
        guard let extensionId = body["extensionId"] as? String else {
            print("❌ [ExtensionManager+Commands] Missing extensionId")
            return
        }
        
        guard let method = body["method"] as? String else {
            print("❌ [ExtensionManager+Commands] Missing method")
            return
        }
        
        let args = body["args"] as? [String: Any] ?? [:]
        let messageId = body["messageId"] as? String ?? UUID().uuidString
        
        // Route to appropriate handler
        let replyHandler: (Any?) -> Void = { [weak self] response in
            self?.sendCommandsResponse(messageId: messageId, response: response, to: message.webView)
        }
        
        switch method {
        case "getAll":
            handleCommandsGetAll(args, from: extensionId, replyHandler: replyHandler)
        default:
            print("❌ [ExtensionManager+Commands] Unknown method: \(method)")
            replyHandler(["error": "Unknown method: \(method)"])
        }
    }
    
    private func sendCommandsResponse(messageId: String, response: Any?, to webView: WKWebView?) {
        guard let webView = webView else {
            print("❌ [ExtensionManager+Commands] No web view for response")
            return
        }
        
        let responseJson = jsonString(from: response ?? [:])
        let script = """
        (function() {
            if (window.__chromeCommandsCallbacks && window.__chromeCommandsCallbacks['\(messageId)']) {
                window.__chromeCommandsCallbacks['\(messageId)'](\(responseJson));
                delete window.__chromeCommandsCallbacks['\(messageId)'];
            }
        })();
        """
        
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ [ExtensionManager+Commands] Error sending response: \(error)")
            }
        }
    }
    
    // MARK: - API Injection
    
    func injectCommandsAPI(into webView: WKWebView, for extensionId: String) {
        print("💉 [ExtensionManager+Commands] Injecting commands API for extension: \(extensionId)")
        
        let script = generateCommandsAPIScript(extensionId: extensionId)
        
        webView.evaluateJavaScript(script) { _, error in
            if let error = error {
                print("❌ [ExtensionManager+Commands] Error injecting commands API: \(error)")
            } else {
                print("✅ [ExtensionManager+Commands] Commands API injected")
            }
        }
    }
    
    func generateCommandsAPIScript(extensionId: String) -> String {
        return """
        (function() {
            'use strict';
            
            console.log('⌨️ [Commands API] Initializing chrome.commands for extension: \(extensionId)');
            
            if (!window.chrome) {
                window.chrome = {};
            }
            
            if (window.chrome.commands) {
                console.log('⚠️ [Commands API] chrome.commands already exists, skipping initialization');
                return;
            }
            
            // Callback storage
            if (!window.__chromeCommandsCallbacks) {
                window.__chromeCommandsCallbacks = {};
            }
            
            // Message counter for unique IDs
            let messageCounter = 0;
            
            function sendCommandsMessage(method, args, callback) {
                const messageId = 'commands_' + (++messageCounter) + '_' + Date.now();
                
                // Store callback if provided
                if (callback) {
                    window.__chromeCommandsCallbacks[messageId] = callback;
                }
                
                const message = {
                    extensionId: '\(extensionId)',
                    method: method,
                    args: args,
                    messageId: messageId
                };
                
                try {
                    window.webkit.messageHandlers.chromeCommands.postMessage(message);
                } catch (error) {
                    console.error('[Commands API] Error sending message:', error);
                    if (callback) {
                        callback({ error: error.message });
                        delete window.__chromeCommandsCallbacks[messageId];
                    }
                }
                
                return new Promise((resolve, reject) => {
                    if (!callback) {
                        window.__chromeCommandsCallbacks[messageId] = (response) => {
                            if (response && response.error) {
                                reject(new Error(response.error));
                            } else {
                                resolve(response);
                            }
                        };
                    }
                });
            }
            
            chrome.commands = {
                getAll: function(callback) {
                    return sendCommandsMessage('getAll', {}, callback);
                },
                
                onCommand: {
                    _listeners: [],
                    addListener: function(callback) {
                        this._listeners.push(callback);
                        console.log('[Commands API] onCommand listener added');
                    },
                    removeListener: function(callback) {
                        const index = this._listeners.indexOf(callback);
                        if (index > -1) {
                            this._listeners.splice(index, 1);
                        }
                    },
                    hasListener: function(callback) {
                        return this._listeners.indexOf(callback) > -1;
                    },
                    _trigger: function(commandName) {
                        console.log('[Commands API] Command triggered:', commandName);
                        this._listeners.forEach(listener => {
                            try {
                                listener(commandName);
                            } catch (error) {
                                console.error('[Commands API] Error in onCommand listener:', error);
                            }
                        });
                    }
                }
            };
            
            console.log('✅ [Commands API] chrome.commands initialized successfully');
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
