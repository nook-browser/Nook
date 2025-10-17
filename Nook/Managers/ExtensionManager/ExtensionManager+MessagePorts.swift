//
//  ExtensionManager+MessagePorts.swift
//  Nook
//
//  Message Port Management for WKWebExtension
//  Implements native MessagePort handling for background service worker communication
//

import Foundation
import WebKit

// MARK: - Message Port Management
@available(macOS 15.4, *)
extension ExtensionManager {
    
    // MARK: - Port Registration and Lifecycle
    
    /// Register a message port when an extension establishes a connection
    /// This is called from the webExtensionController(_:connectUsing:for:completionHandler:) delegate
    func registerMessagePort(_ port: WKWebExtension.MessagePort, 
                            for extensionContext: WKWebExtensionContext, 
                            portName: String? = nil) {
        let extensionId = extensionContext.uniqueIdentifier
        let displayName = extensionContext.webExtension.displayName ?? "Unknown Extension"
        
        // Determine if this is a background service worker port or a named port
        let isBackgroundPort = (portName == nil || portName == "background" || portName?.isEmpty == true)
        
        if isBackgroundPort {
            // This is a background service worker connection
            print("🔌 [MessagePorts] Registering BACKGROUND service worker port for: \(displayName)")
            backgroundServiceWorkerPorts[extensionId] = port
            
            // Also store in the general ports dictionary with a special key
            let portKey = "\(extensionId):background"
            extensionMessagePortsAccess[portKey] = port
        } else {
            // This is a named port connection (e.g., from runtime.connect({name: "myPort"}))
            let actualPortName = portName ?? "unnamed"
            print("🔌 [MessagePorts] Registering NAMED port '\(actualPortName)' for: \(displayName)")
            
            let portKey = "\(extensionId):\(actualPortName)"
            extensionMessagePortsAccess[portKey] = port
        }
        
        // Set up disconnect handler
        setupPortDisconnectHandler(port, extensionId: extensionId, portName: portName)
        
        print("✅ [MessagePorts] Port registered successfully")
        print("   Extension: \(displayName)")
        print("   Extension ID: \(extensionId)")
        print("   Port Type: \(isBackgroundPort ? "Background Service Worker" : "Named Port (\(portName ?? "unnamed"))")")
        print("   Total active ports: \(extensionMessagePortsAccess.count)")
    }
    
    /// Set up a disconnect handler for a message port
    private func setupPortDisconnectHandler(_ port: WKWebExtension.MessagePort, 
                                           extensionId: String, 
                                           portName: String?) {
        // Note: WKWebExtension.MessagePort doesn't expose a direct disconnect callback API
        // The port's isDisconnected property will be checked before sending messages
        // Cleanup happens in disconnectAllMessagePorts or when detecting disconnection
    }
    
    /// Get the background service worker port for an extension
    func getBackgroundPort(for extensionContext: WKWebExtensionContext) -> WKWebExtension.MessagePort? {
        let extensionId = extensionContext.uniqueIdentifier
        return getBackgroundPort(for: extensionId)
    }
    
    /// Get the background service worker port for an extension by ID
    func getBackgroundPort(for extensionId: String) -> WKWebExtension.MessagePort? {
        guard let port = backgroundServiceWorkerPorts[extensionId] else {
            print("⚠️ [MessagePorts] No background port found for extension: \(extensionId)")
            return nil
        }
        
        // Check if port is still connected
        if port.isDisconnected {
            print("⚠️ [MessagePorts] Background port is disconnected for extension: \(extensionId)")
            backgroundServiceWorkerPorts.removeValue(forKey: extensionId)
            return nil
        }
        
        return port
    }
    
    /// Get a named port for an extension
    func getNamedPort(portName: String, for extensionContext: WKWebExtensionContext) -> WKWebExtension.MessagePort? {
        let extensionId = extensionContext.uniqueIdentifier
        let portKey = "\(extensionId):\(portName)"
        
        guard let port = extensionMessagePortsAccess[portKey] else {
            print("⚠️ [MessagePorts] No port named '\(portName)' found for extension: \(extensionId)")
            return nil
        }
        
        // Check if port is still connected
        if port.isDisconnected {
            print("⚠️ [MessagePorts] Port '\(portName)' is disconnected for extension: \(extensionId)")
            extensionMessagePortsAccess.removeValue(forKey: portKey)
            return nil
        }
        
        return port
    }
    
    /// Get all active ports for an extension
    func getAllPorts(for extensionId: String) -> [String: WKWebExtension.MessagePort] {
        var ports: [String: WKWebExtension.MessagePort] = [:]
        
        // Filter ports by extension ID prefix
        for (key, port) in extensionMessagePortsAccess {
            if key.hasPrefix("\(extensionId):") {
                // Remove disconnected ports
                if port.isDisconnected {
                    extensionMessagePortsAccess.removeValue(forKey: key)
                    continue
                }
                
                // Extract port name from key
                let portName = String(key.dropFirst("\(extensionId):".count))
                ports[portName] = port
            }
        }
        
        return ports
    }
    
    /// Disconnect a specific port
    func disconnectPort(portName: String, for extensionId: String) {
        let portKey = "\(extensionId):\(portName)"
        
        guard let port = extensionMessagePortsAccess[portKey] else {
            print("⚠️ [MessagePorts] Cannot disconnect - port '\(portName)' not found for extension: \(extensionId)")
            return
        }
        
        if !port.isDisconnected {
            port.disconnect()
            print("🔌 [MessagePorts] Disconnected port '\(portName)' for extension: \(extensionId)")
        }
        
        extensionMessagePortsAccess.removeValue(forKey: portKey)
        
        // If this was the background port, also remove from background ports dictionary
        if portName == "background" {
            backgroundServiceWorkerPorts.removeValue(forKey: extensionId)
        }
    }
    
    /// Disconnect all ports for an extension (called during extension unload)
    func disconnectAllPorts(for extensionId: String) {
        print("🔌 [MessagePorts] Disconnecting all ports for extension: \(extensionId)")
        
        var disconnectedCount = 0
        
        // Find all ports for this extension
        let portsToDisconnect = extensionMessagePortsAccess.filter { key, _ in
            key.hasPrefix("\(extensionId):")
        }
        
        // Disconnect each port
        for (portKey, port) in portsToDisconnect {
            if !port.isDisconnected {
                port.disconnect()
                disconnectedCount += 1
            }
            extensionMessagePortsAccess.removeValue(forKey: portKey)
        }
        
        // Remove from background ports
        backgroundServiceWorkerPorts.removeValue(forKey: extensionId)
        
        print("✅ [MessagePorts] Disconnected \(disconnectedCount) port(s) for extension: \(extensionId)")
    }
    
    // MARK: - Message Sending via Ports
    
    /// Send a message to the background service worker
    func sendMessageToBackground(_ message: Any, 
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: ((Any?, Error?) -> Void)? = nil) {
        let extensionId = extensionContext.uniqueIdentifier
        let displayName = extensionContext.webExtension.displayName ?? "Unknown"
        
        guard let backgroundPort = getBackgroundPort(for: extensionId) else {
            let error = NSError(domain: "ExtensionManager", 
                              code: 1001, 
                              userInfo: [NSLocalizedDescriptionKey: "No background service worker port available"])
            print("❌ [MessagePorts] Cannot send to background - no port for: \(displayName)")
            completionHandler?(nil, error)
            return
        }
        
        // Extract or generate message ID for response tracking
        let messageId: String
        if let messageDict = message as? [String: Any], let id = messageDict["id"] as? String {
            messageId = id
        } else {
            messageId = UUID().uuidString
            print("⚠️ [MessagePorts] Message missing ID, generated: \(messageId)")
        }
        
        print("📤 [MessagePorts] Sending message to background service worker: \(displayName)")
        print("   Message ID: \(messageId)")
        print("   Message: \(message)")
        
        // Store the completion handler for when the response comes back
        if let handler = completionHandler {
            storePendingResponse(messageId: messageId, handler: handler)
            print("   ✅ Stored pending response handler for message ID: \(messageId)")
            
            // Set timeout for response (10 seconds)
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                guard let self = self else { return }
                
                if let timeoutHandler = self.retrieveAndRemovePendingResponse(messageId: messageId) {
                    print("⏱️ [MessagePorts] Response timeout for message ID: \(messageId)")
                    let timeoutError = NSError(domain: "ExtensionManager",
                                             code: 1002,
                                             userInfo: [NSLocalizedDescriptionKey: "Message response timeout after 10 seconds"])
                    timeoutHandler(nil, timeoutError)
                }
            }
        }
        
        // Send the message via MessagePort
        backgroundPort.sendMessage(message) { [weak self] error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ [MessagePorts] Failed to send message to background: \(error.localizedDescription)")
                
                // Remove pending handler on delivery failure
                if let failureHandler = self.retrieveAndRemovePendingResponse(messageId: messageId) {
                    failureHandler(nil, error)
                }
            } else {
                print("✅ [MessagePorts] Message delivered to background service worker")
                print("   ⏳ Waiting for response for message ID: \(messageId)")
                // Don't call completion handler yet - wait for actual response!
                // The response will come back through the webExtensionController delegate
            }
        }
    }
    
    /// Send a message to a named port
    func sendMessageToPort(portName: String,
                          message: Any,
                          for extensionContext: WKWebExtensionContext,
                          completionHandler: ((Any?, Error?) -> Void)? = nil) {
        let extensionId = extensionContext.uniqueIdentifier
        let displayName = extensionContext.webExtension.displayName ?? "Unknown"
        
        guard let port = getNamedPort(portName: portName, for: extensionContext) else {
            let error = NSError(domain: "ExtensionManager",
                              code: 1002,
                              userInfo: [NSLocalizedDescriptionKey: "Port '\(portName)' not found"])
            print("❌ [MessagePorts] Cannot send to port '\(portName)' - not found for: \(displayName)")
            completionHandler?(nil, error)
            return
        }
        
        print("📤 [MessagePorts] Sending message to port '\(portName)': \(displayName)")
        print("   Message: \(message)")
        
        port.sendMessage(message) { error in
            if let error = error {
                print("❌ [MessagePorts] Failed to send message to port '\(portName)': \(error.localizedDescription)")
                completionHandler?(nil, error)
            } else {
                print("✅ [MessagePorts] Message delivered to port '\(portName)'")
                completionHandler?(["success": true], nil)
            }
        }
    }
    
    /// Send a structured event to the background service worker
    /// This is used for commands, context menu clicks, alarms, etc.
    func sendEventToBackground(eventType: String,
                               eventData: [String: Any],
                               for extensionContext: WKWebExtensionContext,
                               completionHandler: ((Any?, Error?) -> Void)? = nil) {
        let extensionId = extensionContext.uniqueIdentifier
        let displayName = extensionContext.webExtension.displayName ?? "Unknown"
        
        // Create a structured event message
        let eventMessage: [String: Any] = [
            "type": "event",
            "eventType": eventType,
            "data": eventData,
            "timestamp": Date().timeIntervalSince1970
        ]
        
        print("📡 [MessagePorts] Sending event '\(eventType)' to background: \(displayName)")
        
        sendMessageToBackground(eventMessage, for: extensionContext, completionHandler: completionHandler)
    }
    
    // MARK: - Port Statistics and Debugging
    
    /// Get statistics about active message ports
    func getPortStatistics() -> [String: Any] {
        var stats: [String: Any] = [:]
        
        // Count total ports
        stats["totalPorts"] = extensionMessagePortsAccess.count
        stats["backgroundPorts"] = backgroundServiceWorkerPorts.count
        
        // Count ports per extension
        var portsByExtension: [String: Int] = [:]
        for (key, port) in extensionMessagePortsAccess {
            if !port.isDisconnected {
                let extensionId = key.components(separatedBy: ":").first ?? "unknown"
                portsByExtension[extensionId, default: 0] += 1
            }
        }
        stats["portsByExtension"] = portsByExtension
        
        // Count disconnected ports (for cleanup monitoring)
        let disconnectedCount = extensionMessagePortsAccess.values.filter { $0.isDisconnected }.count
        stats["disconnectedPorts"] = disconnectedCount
        
        return stats
    }
    
    /// Clean up disconnected ports
    func cleanupDisconnectedPorts() {
        var cleanedCount = 0
        
        // Remove disconnected ports from main dictionary
        let disconnectedKeys = extensionMessagePortsAccess.filter { $0.value.isDisconnected }.map { $0.key }
        for key in disconnectedKeys {
            extensionMessagePortsAccess.removeValue(forKey: key)
            cleanedCount += 1
        }
        
        // Remove disconnected background ports
        let disconnectedBackgroundIds = backgroundServiceWorkerPorts.filter { $0.value.isDisconnected }.map { $0.key }
        for extensionId in disconnectedBackgroundIds {
            backgroundServiceWorkerPorts.removeValue(forKey: extensionId)
            cleanedCount += 1
        }
        
        if cleanedCount > 0 {
            print("🧹 [MessagePorts] Cleaned up \(cleanedCount) disconnected port(s)")
        }
    }
}
