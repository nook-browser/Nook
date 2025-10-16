//
//  ExtensionManager+Alarms.swift
//  Nook
//
//  Chrome Alarms API Bridge for WKWebExtension support
//

import Foundation
import WebKit
import AppKit

// MARK: - Alarm Data Structures
@available(macOS 15.4, *)
struct ExtensionAlarm: Codable {
    let name: String
    let scheduledTime: TimeInterval  // Unix timestamp in milliseconds
    let periodInMinutes: Double?     // Optional: for repeating alarms
    let delayInMinutes: Double?      // Original delay requested
    
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "scheduledTime": scheduledTime
        ]
        if let period = periodInMinutes {
            dict["periodInMinutes"] = period
        }
        return dict
    }
}

@available(macOS 15.4, *)
struct AlarmCreateInfo: Codable {
    let when: TimeInterval?          // Unix timestamp when alarm should fire
    let delayInMinutes: Double?      // Delay before alarm fires
    let periodInMinutes: Double?     // Period for repeating alarms
}

// MARK: - Chrome Alarms API Bridge
@available(macOS 15.4, *)
extension ExtensionManager {
    
    // Storage for active alarms per extension
    private static var extensionAlarms: [String: [String: ExtensionAlarm]] = [:]  // extensionId -> alarmName -> alarm
    private static var extensionTimers: [String: [String: Timer]] = [:]            // extensionId -> alarmName -> timer
    private static var alarmsLock = NSLock()
    
    // MARK: - Alarms API Implementation
    
    /// Handles chrome.alarms API calls from extension contexts
    func handleAlarmsMessage(message: [String: Any], from context: WKWebExtensionContext, replyHandler: @escaping (Any?) -> Void) {
        print("🔔 [ExtensionManager+Alarms] === CHROME ALARMS API CALL ===")
        print("🔔 [ExtensionManager+Alarms] Message keys: \(message.keys)")
        
        guard let extensionId = getExtensionId(for: context) else {
            print("❌ [ExtensionManager+Alarms] Extension ID not found")
            replyHandler(["error": "Extension ID not found"])
            return
        }
        
        guard let action = message["action"] as? String else {
            print("❌ [ExtensionManager+Alarms] No action specified")
            replyHandler(["error": "No action specified"])
            return
        }
        
        print("🔔 [ExtensionManager+Alarms] Action: \(action), Extension: \(extensionId)")
        
        switch action {
        case "create":
            handleAlarmsCreate(message: message, extensionId: extensionId, context: context, replyHandler: replyHandler)
        case "get":
            handleAlarmsGet(message: message, extensionId: extensionId, replyHandler: replyHandler)
        case "getAll":
            handleAlarmsGetAll(extensionId: extensionId, replyHandler: replyHandler)
        case "clear":
            handleAlarmsClear(message: message, extensionId: extensionId, replyHandler: replyHandler)
        case "clearAll":
            handleAlarmsClearAll(extensionId: extensionId, replyHandler: replyHandler)
        default:
            print("❌ [ExtensionManager+Alarms] Unknown action: \(action)")
            replyHandler(["error": "Unknown alarms action: \(action)"])
        }
    }
    
    // MARK: - chrome.alarms.create()
    
    private func handleAlarmsCreate(message: [String: Any], extensionId: String, context: WKWebExtensionContext, replyHandler: @escaping (Any?) -> Void) {
        let name = message["name"] as? String ?? ""
        
        // Handle missing or invalid alarmInfo
        guard let alarmInfo = message["alarmInfo"] else {
            print("❌ [ExtensionManager+Alarms] No alarm info provided")
            replyHandler(["error": "Invalid call to alarms.create(). The 'info' value is invalid, because an object is expected."])
            return
        }
        
        guard let alarmInfoDict = alarmInfo as? [String: Any] else {
            print("❌ [ExtensionManager+Alarms] Alarm info is not a dictionary: \(type(of: alarmInfo))")
            replyHandler(["error": "Invalid call to alarms.create(). The 'info' value is invalid, because an object is expected."])
            return
        }
        
        print("🔔 [ExtensionManager+Alarms] Creating alarm '\(name)' for extension \(extensionId)")
        print("🔔 [ExtensionManager+Alarms] Alarm info: \(alarmInfoDict)")
        
        // Parse alarm creation info
        let when = alarmInfoDict["when"] as? TimeInterval
        let delayInMinutes = alarmInfoDict["delayInMinutes"] as? Double
        let periodInMinutes = alarmInfoDict["periodInMinutes"] as? Double
        
        // Calculate scheduled time
        let now = Date().timeIntervalSince1970 * 1000  // Convert to milliseconds
        var scheduledTime: TimeInterval
        
        if let when = when {
            scheduledTime = when
        } else if let delay = delayInMinutes {
            scheduledTime = now + (delay * 60 * 1000)
        } else {
            // Default to immediate if no time specified
            scheduledTime = now
        }
        
        // Create alarm object
        let alarm = ExtensionAlarm(
            name: name,
            scheduledTime: scheduledTime,
            periodInMinutes: periodInMinutes,
            delayInMinutes: delayInMinutes
        )
        
        // Store alarm
        Self.alarmsLock.lock()
        if Self.extensionAlarms[extensionId] == nil {
            Self.extensionAlarms[extensionId] = [:]
        }
        if Self.extensionTimers[extensionId] == nil {
            Self.extensionTimers[extensionId] = [:]
        }
        
        // Clear existing alarm with same name
        if let existingTimer = Self.extensionTimers[extensionId]?[name] {
            existingTimer.invalidate()
        }
        
        Self.extensionAlarms[extensionId]?[name] = alarm
        Self.alarmsLock.unlock()
        
        // Schedule timer
        scheduleAlarm(alarm: alarm, extensionId: extensionId, context: context)
        
        print("✅ [ExtensionManager+Alarms] Alarm '\(name)' created and scheduled")
        replyHandler(["success": true])
    }
    
    // MARK: - chrome.alarms.get()
    
    private func handleAlarmsGet(message: [String: Any], extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        guard let name = message["name"] as? String else {
            replyHandler(["error": "No alarm name provided"])
            return
        }
        
        Self.alarmsLock.lock()
        let alarm = Self.extensionAlarms[extensionId]?[name]
        Self.alarmsLock.unlock()
        
        if let alarm = alarm {
            print("🔔 [ExtensionManager+Alarms] Retrieved alarm '\(name)'")
            replyHandler(["alarm": alarm.dictionary])
        } else {
            print("🔔 [ExtensionManager+Alarms] Alarm '\(name)' not found")
            replyHandler(["alarm": NSNull()])
        }
    }
    
    // MARK: - chrome.alarms.getAll()
    
    private func handleAlarmsGetAll(extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        Self.alarmsLock.lock()
        let alarms = Self.extensionAlarms[extensionId]?.values.map { $0.dictionary } ?? []
        Self.alarmsLock.unlock()
        
        print("🔔 [ExtensionManager+Alarms] Retrieved \(alarms.count) alarms")
        replyHandler(["alarms": alarms])
    }
    
    // MARK: - chrome.alarms.clear()
    
    private func handleAlarmsClear(message: [String: Any], extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        guard let name = message["name"] as? String else {
            replyHandler(["error": "No alarm name provided"])
            return
        }
        
        Self.alarmsLock.lock()
        let wasCleared = Self.extensionAlarms[extensionId]?[name] != nil
        Self.extensionAlarms[extensionId]?[name] = nil
        
        if let timer = Self.extensionTimers[extensionId]?[name] {
            timer.invalidate()
            Self.extensionTimers[extensionId]?[name] = nil
        }
        Self.alarmsLock.unlock()
        
        print("🔔 [ExtensionManager+Alarms] Alarm '\(name)' cleared: \(wasCleared)")
        replyHandler(["wasCleared": wasCleared])
    }
    
    // MARK: - chrome.alarms.clearAll()
    
    private func handleAlarmsClearAll(extensionId: String, replyHandler: @escaping (Any?) -> Void) {
        Self.alarmsLock.lock()
        let count = Self.extensionAlarms[extensionId]?.count ?? 0
        
        // Invalidate all timers
        Self.extensionTimers[extensionId]?.values.forEach { $0.invalidate() }
        
        // Clear all alarms
        Self.extensionAlarms[extensionId] = [:]
        Self.extensionTimers[extensionId] = [:]
        Self.alarmsLock.unlock()
        
        print("🔔 [ExtensionManager+Alarms] Cleared all \(count) alarms")
        replyHandler(["wasCleared": count > 0])
    }
    
    // MARK: - Timer Management
    
    private func scheduleAlarm(alarm: ExtensionAlarm, extensionId: String, context: WKWebExtensionContext) {
        let now = Date().timeIntervalSince1970 * 1000
        let delay = max(0, (alarm.scheduledTime - now) / 1000)  // Convert to seconds
        
        print("🔔 [ExtensionManager+Alarms] Scheduling alarm '\(alarm.name)' in \(delay) seconds")
        
        // Create timer
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.fireAlarm(alarm: alarm, extensionId: extensionId, context: context)
        }
        
        // Store timer
        Self.alarmsLock.lock()
        Self.extensionTimers[extensionId]?[alarm.name] = timer
        Self.alarmsLock.unlock()
        
        // Add to run loop
        RunLoop.main.add(timer, forMode: .common)
    }
    
    private func fireAlarm(alarm: ExtensionAlarm, extensionId: String, context: WKWebExtensionContext) {
        print("🔔 [ExtensionManager+Alarms] 🔥 FIRING ALARM '\(alarm.name)' for extension \(extensionId)")
        
        // Dispatch onAlarm event to extension
        dispatchAlarmEvent(alarm: alarm, context: context)
        
        // Handle repeating alarms
        if let periodInMinutes = alarm.periodInMinutes {
            print("🔔 [ExtensionManager+Alarms] Rescheduling repeating alarm '\(alarm.name)' (period: \(periodInMinutes) min)")
            
            // Calculate next scheduled time
            let nextScheduledTime = alarm.scheduledTime + (periodInMinutes * 60 * 1000)
            let nextAlarm = ExtensionAlarm(
                name: alarm.name,
                scheduledTime: nextScheduledTime,
                periodInMinutes: periodInMinutes,
                delayInMinutes: alarm.delayInMinutes
            )
            
            // Update stored alarm
            Self.alarmsLock.lock()
            Self.extensionAlarms[extensionId]?[alarm.name] = nextAlarm
            Self.alarmsLock.unlock()
            
            // Schedule next occurrence
            scheduleAlarm(alarm: nextAlarm, extensionId: extensionId, context: context)
        } else {
            // One-time alarm - remove it
            print("🔔 [ExtensionManager+Alarms] Removing one-time alarm '\(alarm.name)'")
            Self.alarmsLock.lock()
            Self.extensionAlarms[extensionId]?[alarm.name] = nil
            Self.extensionTimers[extensionId]?[alarm.name] = nil
            Self.alarmsLock.unlock()
        }
    }
    
    private func dispatchAlarmEvent(alarm: ExtensionAlarm, context: WKWebExtensionContext) {
        // Get background webview for this extension
        guard let backgroundWebView = getBackgroundWebView(for: context) else {
            print("❌ [ExtensionManager+Alarms] No background webview found for alarm dispatch")
            return
        }
        
        let alarmDict = alarm.dictionary
        let alarmJSON = try? JSONSerialization.data(withJSONObject: alarmDict, options: [])
        let alarmJSONString = alarmJSON.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        
        let script = """
        (function() {
            if (typeof chrome !== 'undefined' && chrome.alarms && chrome.alarms.onAlarm) {
                const alarm = \(alarmJSONString);
                console.log('🔔 [Alarms] Dispatching onAlarm event:', alarm);
                chrome.alarms.onAlarm.dispatch(alarm);
            } else {
                console.error('❌ [Alarms] chrome.alarms.onAlarm not available');
            }
        })();
        """
        
        Task { @MainActor in
            backgroundWebView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    print("❌ [ExtensionManager+Alarms] Error dispatching alarm event: \(error)")
                } else {
                    print("✅ [ExtensionManager+Alarms] Alarm event dispatched successfully")
                }
            }
        }
    }
    
    // MARK: - JavaScript API Injection
    
    /// Generates the chrome.alarms JavaScript API
    func generateAlarmsAPIScript(extensionId: String) -> String {
        return """
        // chrome.alarms API Implementation
        (function() {
            if (typeof chrome === 'undefined') {
                console.error('❌ [Alarms] Chrome namespace not available');
                return;
            }
            
            console.log('🔔 [Alarms] Initializing chrome.alarms API');
            
            chrome.alarms = {
                create: function(name, alarmInfo, callback) {
                    console.log('🔔 [Alarms] create() called:', name, alarmInfo);
                    
                    // Handle overloaded parameters: create(alarmInfo, callback) or create(name, alarmInfo, callback)
                    if (typeof name === 'object') {
                        callback = alarmInfo;
                        alarmInfo = name;
                        name = '';
                    }
                    
                    // Ensure alarmInfo is a valid object
                    if (typeof alarmInfo !== 'object' || alarmInfo === null) {
                        console.error('❌ [Alarms] alarmInfo must be an object, got:', typeof alarmInfo);
                        const error = new Error("Invalid call to alarms.create(). The 'info' value is invalid, because an object is expected.");
                        chrome.runtime.lastError = { message: error.message };
                        if (callback) callback();
                        delete chrome.runtime.lastError;
                        return;
                    }
                    
                    const message = {
                        api: 'alarms',
                        action: 'create',
                        name: name || '',
                        alarmInfo: alarmInfo
                    };
                    
                    window.webkit.messageHandlers.extensionAPI.postMessage(message).then(function(response) {
                        console.log('🔔 [Alarms] create() response:', response);
                        if (callback) callback();
                    }).catch(function(error) {
                        console.error('❌ [Alarms] create() error:', error);
                        chrome.runtime.lastError = { message: error.toString() };
                        if (callback) callback();
                        delete chrome.runtime.lastError;
                    });
                },
                
                get: function(name, callback) {
                    console.log('🔔 [Alarms] get() called:', name);
                    
                    // Handle overload: get(callback) returns all alarms
                    if (typeof name === 'function') {
                        callback = name;
                        name = undefined;
                    }
                    
                    if (!name) {
                        chrome.alarms.getAll(callback);
                        return;
                    }
                    
                    const message = {
                        api: 'alarms',
                        action: 'get',
                        name: name
                    };
                    
                    window.webkit.messageHandlers.extensionAPI.postMessage(message).then(function(response) {
                        console.log('🔔 [Alarms] get() response:', response);
                        if (callback) callback(response.alarm);
                    }).catch(function(error) {
                        console.error('❌ [Alarms] get() error:', error);
                        chrome.runtime.lastError = { message: error.toString() };
                        if (callback) callback(undefined);
                        delete chrome.runtime.lastError;
                    });
                },
                
                getAll: function(callback) {
                    console.log('🔔 [Alarms] getAll() called');
                    
                    const message = {
                        api: 'alarms',
                        action: 'getAll'
                    };
                    
                    window.webkit.messageHandlers.extensionAPI.postMessage(message).then(function(response) {
                        console.log('🔔 [Alarms] getAll() response:', response);
                        if (callback) callback(response.alarms || []);
                    }).catch(function(error) {
                        console.error('❌ [Alarms] getAll() error:', error);
                        chrome.runtime.lastError = { message: error.toString() };
                        if (callback) callback([]);
                        delete chrome.runtime.lastError;
                    });
                },
                
                clear: function(name, callback) {
                    console.log('🔔 [Alarms] clear() called:', name);
                    
                    // Handle overload: clear(callback) clears all alarms
                    if (typeof name === 'function') {
                        callback = name;
                        chrome.alarms.clearAll(callback);
                        return;
                    }
                    
                    const message = {
                        api: 'alarms',
                        action: 'clear',
                        name: name
                    };
                    
                    window.webkit.messageHandlers.extensionAPI.postMessage(message).then(function(response) {
                        console.log('🔔 [Alarms] clear() response:', response);
                        if (callback) callback(response.wasCleared || false);
                    }).catch(function(error) {
                        console.error('❌ [Alarms] clear() error:', error);
                        chrome.runtime.lastError = { message: error.toString() };
                        if (callback) callback(false);
                        delete chrome.runtime.lastError;
                    });
                },
                
                clearAll: function(callback) {
                    console.log('🔔 [Alarms] clearAll() called');
                    
                    const message = {
                        api: 'alarms',
                        action: 'clearAll'
                    };
                    
                    window.webkit.messageHandlers.extensionAPI.postMessage(message).then(function(response) {
                        console.log('🔔 [Alarms] clearAll() response:', response);
                        if (callback) callback(response.wasCleared || false);
                    }).catch(function(error) {
                        console.error('❌ [Alarms] clearAll() error:', error);
                        chrome.runtime.lastError = { message: error.toString() };
                        if (callback) callback(false);
                        delete chrome.runtime.lastError;
                    });
                },
                
                onAlarm: {
                    _listeners: [],
                    addListener: function(listener) {
                        console.log('🔔 [Alarms] onAlarm.addListener() called');
                        if (typeof listener === 'function') {
                            this._listeners.push(listener);
                        }
                    },
                    removeListener: function(listener) {
                        const index = this._listeners.indexOf(listener);
                        if (index > -1) {
                            this._listeners.splice(index, 1);
                        }
                    },
                    hasListener: function(listener) {
                        return this._listeners.indexOf(listener) > -1;
                    },
                    dispatch: function(alarm) {
                        console.log('🔔 [Alarms] Dispatching alarm to', this._listeners.length, 'listeners');
                        this._listeners.forEach(function(listener) {
                            try {
                                listener(alarm);
                            } catch (e) {
                                console.error('❌ [Alarms] Error in alarm listener:', e);
                            }
                        });
                    }
                }
            };
            
            console.log('✅ [Alarms] chrome.alarms API initialized');
        })();
        """
    }
}
