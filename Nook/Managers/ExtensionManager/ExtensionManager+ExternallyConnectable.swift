//
//  ExtensionManager+ExternallyConnectable.swift
//  Nook
//
//  Externally Connectable Bridge — page-world polyfill and manifest patching
//

import AppKit
import Foundation
import os
import WebKit

@available(macOS 15.4, *)
extension ExtensionManager {

    // MARK: - Externally Connectable Bridge

    /// Set up the externally_connectable bridge for an extension.
    ///
    /// Problem: Web pages (like account.proton.me) call browser.runtime.sendMessage(SAFARI_EXT_ID, msg)
    /// to communicate with the extension. The Safari extension ID doesn't match our WKWebExtension
    /// uniqueIdentifier, so the call fails and the page shows an error.
    ///
    /// Fix: Inject a user script into matching pages that wraps browser.runtime.sendMessage.
    /// When called with an external extensionId, it strips the ID and forwards as a regular
    /// content-script-to-background message (which the background handles — this is the same
    /// path Firefox uses via its postMessage fallback).
    @available(macOS 15.4, *)
    func setupExternallyConnectableBridge(
        for extensionContext: WKWebExtensionContext,
        extensionId: String,
        packagePath: String
    ) {
        let manifestURL = URL(fileURLWithPath: packagePath).appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ec = manifest["externally_connectable"] as? [String: Any],
              let matchPatterns = ec["matches"] as? [String], !matchPatterns.isEmpty
        else { return }

        // Extract hostnames from match patterns
        var hostnames = Set<String>()
        for pattern in matchPatterns {
            guard let schemeEnd = pattern.range(of: "://") else { continue }
            let afterScheme = pattern[schemeEnd.upperBound...]
            guard let slashIndex = afterScheme.firstIndex(of: "/") else { continue }
            let host = String(afterScheme[afterScheme.startIndex..<slashIndex])
            if host != "*" {
                hostnames.insert(host.replacingOccurrences(of: "*.", with: ""))
            }
        }
        let sortedHostnames = hostnames.sorted()
        guard !sortedHostnames.isEmpty else { return }

        Self.logger.info("Installing page-world externally_connectable polyfill for extension \(extensionId, privacy: .public): \(sortedHostnames.joined(separator: ", "), privacy: .public)")

        let hostnamesJSON = sortedHostnames.map { "\"\($0)\"" }.joined(separator: ",")
        let escapedTargetRuntimeId = extensionId
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // PAGE-world polyfill: wraps browser/chrome runtime APIs used by externally_connectable
        // pages and relays extension traffic via window.postMessage to nook_bridge.js (ISOLATED world).
        let polyfillJS = """
        (function() {
            var _hosts = [\(hostnamesJSON)];
            var _configuredRuntimeId = "\(escapedTargetRuntimeId)";
            var _activeRuntimeId = _configuredRuntimeId;
            var _pendingBridgeRuntimeId = null;
            var _bridgeRuntimeRetargetTimer = null;
            var h = location.hostname;
            if (!_hosts.some(function(p) { return h === p || h.endsWith('.' + p); })) return;
            if (window.__nookEcShimInstalled) return;
            window.__nookEcShimInstalled = true;

            console.log('[NOOK-EC] Installing externally_connectable polyfill on ' + location.href);

            var bridgeReady = false;
            var bridgeWaiters = [];
            var bridgePorts = Object.create(null);
            var bridgeRequestDedup = Object.create(null);

            function makeEvent() {
                var listeners = [];
                return {
                    addListener: function(fn) {
                        if (typeof fn !== 'function') return;
                        if (listeners.indexOf(fn) >= 0) return;
                        listeners.push(fn);
                    },
                    removeListener: function(fn) {
                        var idx = listeners.indexOf(fn);
                        if (idx >= 0) listeners.splice(idx, 1);
                    },
                    hasListener: function(fn) {
                        return listeners.indexOf(fn) >= 0;
                    },
                    dispatch: function() {
                        var args = Array.prototype.slice.call(arguments);
                        var snapshot = listeners.slice();
                        for (var i = 0; i < snapshot.length; i += 1) {
                            try {
                                snapshot[i].apply(null, args);
                            } catch (error) {
                                console.error('[NOOK-EC] Listener error:', error);
                            }
                        }
                    }
                };
            }

            function markBridgeReady() {
                if (bridgeReady) return;
                bridgeReady = true;
                while (bridgeWaiters.length) {
                    try { bridgeWaiters.shift()(); } catch (_) {}
                }
            }

            function activeRuntimeId() {
                return _activeRuntimeId || _configuredRuntimeId;
            }

            function matchesActiveRuntimeId(runtimeId) {
                if (!runtimeId || typeof runtimeId !== 'string') return true;
                return runtimeId === activeRuntimeId();
            }

            function adoptBridgeRuntime(runtimeId) {
                if (!runtimeId || typeof runtimeId !== 'string') {
                    markBridgeReady();
                    return;
                }

                if (runtimeId === _configuredRuntimeId || runtimeId === _activeRuntimeId) {
                    _activeRuntimeId = runtimeId;
                    markBridgeReady();
                    return;
                }

                if (_activeRuntimeId !== _configuredRuntimeId) {
                    return;
                }

                _pendingBridgeRuntimeId = runtimeId;
                if (_bridgeRuntimeRetargetTimer !== null) return;

                _bridgeRuntimeRetargetTimer = setTimeout(function() {
                    _bridgeRuntimeRetargetTimer = null;
                    if (bridgeReady || !_pendingBridgeRuntimeId) return;
                    _activeRuntimeId = _pendingBridgeRuntimeId;
                    console.warn('[NOOK-EC] Bridge runtime mismatch; retargeting to ' + _activeRuntimeId + ' (configured ' + _configuredRuntimeId + ')');
                    markBridgeReady();
                }, 250);
            }

            function waitForBridgeReady(timeoutMs) {
                if (bridgeReady) return Promise.resolve();
                return new Promise(function(resolve, reject) {
                    var settled = false;
                    var timer = null;

                    var waiter = function() {
                        if (settled) return;
                        settled = true;
                        if (timer !== null) clearTimeout(timer);
                        resolve();
                    };

                    bridgeWaiters.push(waiter);

                    timer = setTimeout(function() {
                        if (settled) return;
                        settled = true;
                        var idx = bridgeWaiters.indexOf(waiter);
                        if (idx >= 0) bridgeWaiters.splice(idx, 1);
                        reject(new Error('Extension bridge unavailable'));
                    }, timeoutMs);
                });
            }

            function normalizeSendMessageArgs(argsLike) {
                var args = Array.prototype.slice.call(argsLike);
                var callback = null;

                if (args.length && typeof args[args.length - 1] === 'function') {
                    callback = args.pop();
                }

                var extensionId = null;
                var message = undefined;
                var options = undefined;

                if (args.length === 1) {
                    message = args[0];
                } else if (args.length === 2) {
                    if (typeof args[0] === 'string') {
                        extensionId = args[0];
                        message = args[1];
                    } else {
                        message = args[0];
                        options = args[1];
                    }
                } else if (args.length >= 3) {
                    extensionId = args[0];
                    message = args[1];
                    options = args[2];
                }

                return {
                    extensionId: extensionId,
                    message: message,
                    options: options,
                    callback: callback
                };
            }

            function normalizeConnectArgs(argsLike) {
                var args = Array.prototype.slice.call(argsLike);
                var extensionId = null;
                var connectInfo = {};

                if (args.length === 1) {
                    if (typeof args[0] === 'string') {
                        extensionId = args[0];
                    } else {
                        connectInfo = args[0];
                    }
                } else if (args.length >= 2) {
                    extensionId = args[0];
                    connectInfo = args[1];
                }

                if (!connectInfo || typeof connectInfo !== 'object') {
                    connectInfo = {};
                }

                return {
                    extensionId: extensionId,
                    connectInfo: connectInfo
                };
            }

            function setChromeLastError(error) {
                if (!window.chrome) window.chrome = {};
                if (!window.chrome.runtime) window.chrome.runtime = {};
                if (error) {
                    window.chrome.runtime.lastError = { message: error.message || String(error) };
                } else if (window.chrome.runtime.lastError) {
                    try {
                        delete window.chrome.runtime.lastError;
                    } catch (_) {
                        window.chrome.runtime.lastError = undefined;
                    }
                }
            }

            function clearChromeLastErrorAsync() {
                setTimeout(function() { setChromeLastError(null); }, 0);
            }

            function requestViaBridge(parsed, requestType) {
                var normalizedType = requestType || (
                    (parsed.message && typeof parsed.message === 'object' && parsed.message.type)
                        ? parsed.message.type
                        : typeof parsed.message
                );

                function dedupKeyForRequest() {
                    if (normalizedType !== 'fork') return null;
                    var selector = parsed && parsed.message && parsed.message.payload && parsed.message.payload.selector;
                    if (!selector || typeof selector !== 'string') return null;
                    var runtimeKey = activeRuntimeId();
                    if (!runtimeKey || typeof runtimeKey !== 'string') runtimeKey = '(runtime)';
                    return 'fork:' + runtimeKey + ':' + selector;
                }

                var dedupKey = dedupKeyForRequest();
                if (dedupKey) {
                    var inFlight = bridgeRequestDedup[dedupKey];
                    if (inFlight && typeof inFlight.then === 'function') {
                        console.log('[NOOK-EC] Reusing in-flight request key=' + dedupKey);
                        return inFlight;
                    }
                }

                var promise = waitForBridgeReady(3000).then(function() {
                    return new Promise(function(resolve, reject) {
                        var callbackId = 'nook_ec_' + Math.random().toString(36).slice(2, 11);
                        var timeoutId = null;
                        var settled = false;

                        function cleanup() {
                            window.removeEventListener('message', handler);
                            if (timeoutId !== null) clearTimeout(timeoutId);
                        }

                        function settleSuccess(response) {
                            if (settled) return;
                            settled = true;
                            cleanup();
                            if (normalizedType === 'fork' && response && typeof response === 'object') {
                                console.log('[NOOK-EC] fork response ok=' + String(response.ok) + ' ext=' + (parsed.extensionId || '(none)'));
                            }
                            resolve(response);
                        }

                        function settleError(error) {
                            if (settled) return;
                            settled = true;
                            cleanup();
                            reject(error);
                        }

                        function handler(event) {
                            if (event.source !== window) return;
                            if (event.origin !== window.location.origin) return;
                            if (!event.data || event.data.type !== 'nook_ec_response') return;
                            if (!matchesActiveRuntimeId(event.data.targetRuntimeId)) return;
                            if (event.data.callbackId !== callbackId) return;

                            if (event.data.error) {
                                console.warn('[NOOK-EC] Response error for type=' + normalizedType + ': ' + event.data.error);
                                settleError(new Error(event.data.error));
                            } else {
                                console.log('[NOOK-EC] Response success for type=' + normalizedType);
                                settleSuccess(event.data.response);
                            }
                        }

                        window.addEventListener('message', handler);
                        timeoutId = setTimeout(function() {
                            console.warn('[NOOK-EC] Timeout waiting for response type=' + normalizedType);
                            settleError(new Error('Extension communication timeout'));
                        }, 30000);

                        console.log('[NOOK-EC] Forwarding request type=' + normalizedType + ' ext=' + (parsed.extensionId || '(none)'));
                        window.postMessage({
                            type: 'nook_ec_request',
                            targetRuntimeId: activeRuntimeId(),
                            extensionId: parsed.extensionId,
                            message: parsed.message,
                            options: parsed.options,
                            callbackId: callbackId
                        }, window.location.origin);
                    });
                });

                if (dedupKey) {
                    bridgeRequestDedup[dedupKey] = promise;
                    var clearInFlight = function() {
                        if (bridgeRequestDedup[dedupKey] === promise) {
                            delete bridgeRequestDedup[dedupKey];
                        }
                    };
                    promise.then(clearInFlight).catch(clearInFlight);
                }

                return promise;
            }

            function closeBridgePort(portId, errorMessage) {
                var entry = bridgePorts[portId];
                if (!entry || entry.disconnected) return;
                entry.disconnected = true;
                delete bridgePorts[portId];

                if (errorMessage) {
                    setChromeLastError(new Error(errorMessage));
                    try {
                        entry.onDisconnect.dispatch(entry.port);
                    } finally {
                        clearChromeLastErrorAsync();
                    }
                    return;
                }
                entry.onDisconnect.dispatch(entry.port);
            }

            function createBridgePort(parsed) {
                var portId = 'nook_ec_port_' + Math.random().toString(36).slice(2, 11);
                var connectInfo = parsed.connectInfo || {};
                var onMessage = makeEvent();
                var onDisconnect = makeEvent();

                var entry = {
                    disconnected: false,
                    onMessage: onMessage,
                    onDisconnect: onDisconnect,
                    port: null
                };

                var port = {
                    name: typeof connectInfo.name === 'string' ? connectInfo.name : '',
                    postMessage: function(message) {
                        if (entry.disconnected) throw new Error('Port is disconnected');
                        window.postMessage({
                            type: 'nook_ec_connect_post',
                            targetRuntimeId: activeRuntimeId(),
                            portId: portId,
                            message: message
                        }, window.location.origin);
                    },
                    disconnect: function() {
                        if (entry.disconnected) return;
                        window.postMessage({
                            type: 'nook_ec_connect_close',
                            targetRuntimeId: activeRuntimeId(),
                            portId: portId
                        }, window.location.origin);
                        closeBridgePort(portId, null);
                    },
                    onMessage: onMessage,
                    onDisconnect: onDisconnect
                };
                entry.port = port;
                bridgePorts[portId] = entry;

                waitForBridgeReady(3000).then(function() {
                    console.log('[NOOK-EC] Opening bridge port id=' + portId + ' name=' + port.name + ' ext=' + (parsed.extensionId || '(none)'));
                    window.postMessage({
                        type: 'nook_ec_connect_open',
                        targetRuntimeId: activeRuntimeId(),
                        extensionId: parsed.extensionId,
                        connectInfo: connectInfo,
                        portId: portId
                    }, window.location.origin);
                }).catch(function(error) {
                    var message = (error && error.message) ? error.message : String(error);
                    console.warn('[NOOK-EC] Bridge port open failed id=' + portId + ': ' + message);
                    closeBridgePort(portId, message);
                });

                return port;
            }

            function makeSendMessageWrapper(originalSendMessage, runtimeKind, runtimeObject) {
                return function() {
                    var parsed = normalizeSendMessageArgs(arguments);
                    var requestType = (
                        parsed.message && typeof parsed.message === 'object' && parsed.message.type
                    ) ? parsed.message.type : typeof parsed.message;

                    var shouldBridge = parsed.extensionId !== null || typeof originalSendMessage !== 'function';
                    console.log('[NOOK-EC] sendMessage called via ' + runtimeKind + ' type=' + requestType + ' ext=' + (parsed.extensionId || '(none)') + ' mode=' + (shouldBridge ? 'bridge' : 'native'));

                    var promise;
                    if (shouldBridge) {
                        promise = requestViaBridge(parsed, requestType);
                    } else {
                        try {
                            promise = Promise.resolve(originalSendMessage.apply(runtimeObject, arguments));
                        } catch (error) {
                            promise = Promise.reject(error);
                        }
                        promise = promise.catch(function(error) {
                            var message = (error && error.message) ? error.message : String(error);
                            console.warn('[NOOK-EC] Native sendMessage failed via ' + runtimeKind + ', falling back to bridge: ' + message);
                            return requestViaBridge(parsed, requestType);
                        });
                    }

                    if (parsed.callback) {
                        promise.then(function(response) {
                            setChromeLastError(null);
                            parsed.callback(response);
                        }).catch(function(error) {
                            setChromeLastError(error);
                            try {
                                parsed.callback();
                            } finally {
                                clearChromeLastErrorAsync();
                            }
                        });
                        return;
                    }

                    return promise;
                };
            }

            function makeConnectWrapper(originalConnect, runtimeKind, runtimeObject) {
                return function() {
                    var parsed = normalizeConnectArgs(arguments);
                    var shouldBridge = parsed.extensionId !== null || typeof originalConnect !== 'function';
                    console.log('[NOOK-EC] connect called via ' + runtimeKind + ' ext=' + (parsed.extensionId || '(none)') + ' mode=' + (shouldBridge ? 'bridge' : 'native'));

                    if (shouldBridge) {
                        return createBridgePort(parsed);
                    }

                    try {
                        return originalConnect.apply(runtimeObject, arguments);
                    } catch (error) {
                        var message = (error && error.message) ? error.message : String(error);
                        console.warn('[NOOK-EC] Native connect failed via ' + runtimeKind + ', falling back to bridge: ' + message);
                        return createBridgePort(parsed);
                    }
                };
            }

            function installRuntimeShim(runtimeObject, runtimeKind) {
                if (!runtimeObject || typeof runtimeObject !== 'object') return;

                var currentSendMessage = typeof runtimeObject.sendMessage === 'function'
                    ? runtimeObject.sendMessage
                    : null;
                if (runtimeObject.sendMessage !== runtimeObject.__nookEcWrappedSendMessage) {
                    runtimeObject.__nookEcWrappedSendMessage = makeSendMessageWrapper(
                        currentSendMessage,
                        runtimeKind,
                        runtimeObject
                    );
                    runtimeObject.sendMessage = runtimeObject.__nookEcWrappedSendMessage;
                }

                var currentConnect = typeof runtimeObject.connect === 'function'
                    ? runtimeObject.connect
                    : null;
                if (runtimeObject.connect !== runtimeObject.__nookEcWrappedConnect) {
                    runtimeObject.__nookEcWrappedConnect = makeConnectWrapper(
                        currentConnect,
                        runtimeKind,
                        runtimeObject
                    );
                    runtimeObject.connect = runtimeObject.__nookEcWrappedConnect;
                }
            }

            function ensureRuntimeObject(rootName) {
                if (!window[rootName]) window[rootName] = {};
                if (!window[rootName].runtime) window[rootName].runtime = {};
                return window[rootName].runtime;
            }

            window.addEventListener('message', function(event) {
                if (event.source !== window) return;
                if (event.origin !== window.location.origin) return;
                if (!event.data || typeof event.data.type !== 'string') return;
                if (event.data.type === 'nook_ec_bridge_ready') {
                    adoptBridgeRuntime(event.data.targetRuntimeId);
                    return;
                }
                if (event.data.type === 'nook_ec_connect_message') {
                    if (!matchesActiveRuntimeId(event.data.targetRuntimeId)) return;
                    var messageEntry = bridgePorts[event.data.portId];
                    if (!messageEntry || messageEntry.disconnected) return;
                    messageEntry.onMessage.dispatch(event.data.message, messageEntry.port);
                    return;
                }
                if (event.data.type === 'nook_ec_connect_disconnect') {
                    if (!matchesActiveRuntimeId(event.data.targetRuntimeId)) return;
                    closeBridgePort(event.data.portId, event.data.error || null);
                    return;
                }
            });

            var browserRuntime = ensureRuntimeObject('browser');
            var chromeRuntime = ensureRuntimeObject('chrome');
            installRuntimeShim(browserRuntime, 'browser.runtime');
            installRuntimeShim(chromeRuntime, 'chrome.runtime');

            // Some apps patch runtime methods after page load; re-apply wrappers briefly.
            var shimAttempts = 0;
            var shimTimer = setInterval(function() {
                shimAttempts += 1;
                installRuntimeShim(browserRuntime, 'browser.runtime');
                installRuntimeShim(chromeRuntime, 'chrome.runtime');
                if (shimAttempts >= 60) clearInterval(shimTimer);
            }, 500);

            console.log('[NOOK-EC] Polyfill ready — runtime sendMessage/connect wrapped (configured=' + _configuredRuntimeId + ')');
        })();
        """

        let sharedConfig = BrowserConfiguration.shared.webViewConfiguration
        let hostsSignature = "var _hosts = [\(hostnamesJSON)];"
        let sharedUserContentController = sharedConfig.userContentController
        let retainedScripts = sharedUserContentController.userScripts.filter { script in
            let source = script.source
            guard source.contains("[NOOK-EC] Installing externally_connectable polyfill on ") else {
                return true
            }
            return !source.contains(hostsSignature)
        }
        if retainedScripts.count != sharedUserContentController.userScripts.count {
            sharedUserContentController.removeAllUserScripts()
            retainedScripts.forEach { sharedUserContentController.addUserScript($0) }
            Self.logger.info("Removed stale page-world externally_connectable shim for hosts: \(sortedHostnames.joined(separator: ", "), privacy: .public)")
        }

        let pageScript = WKUserScript(
            source: polyfillJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: .page
        )
        sharedUserContentController.addUserScript(pageScript)
    }

    /// Patch manifest.json so domain-specific content scripts run in MAIN world.
    ///
    /// In Chrome MV3, content script fetch() uses the page's origin. In WebKit's
    /// ISOLATED world, fetch() uses the extension's origin (webkit-extension://)
    /// which causes CORS failures and prevents cookies from being sent. This
    /// particularly breaks SSO/auth flows like Proton Pass's fork session handoff
    /// where a content script needs to make authenticated requests to the page's API.
    ///
    /// The fix: content scripts that target a small set of specific domains (not
    /// wildcard all-sites patterns) and don't already specify a world are patched
    /// to run in MAIN world, where fetch() uses the page's origin and cookies.
    func patchManifestForWebKit(at manifestURL: URL) {
        guard let data = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let extensionDirName = manifestURL.deletingLastPathComponent().lastPathComponent
        var changed = false

        // --- Revert any previous MAIN-world patches on domain-specific content scripts ---
        // (Earlier code incorrectly patched domain-specific scripts to MAIN world,
        // but MAIN world content scripts lose browser.runtime access in WKWebExtension.)
        if var contentScripts = manifest["content_scripts"] as? [[String: Any]] {
            for i in contentScripts.indices {
                guard let world = contentScripts[i]["world"] as? String, world == "MAIN" else { continue }
                guard let matches = contentScripts[i]["matches"] as? [String] else { continue }
                let jsFiles = contentScripts[i]["js"] as? [String] ?? []

                // Don't touch our own bridge entry
                if jsFiles.contains("nook_bridge.js") { continue }

                // If ALL matches are domain-specific (no wildcard hosts), this was likely our patch
                let allDomainSpecific = matches.allSatisfy { pattern in
                    guard let schemeEnd = pattern.range(of: "://") else { return false }
                    let afterScheme = pattern[schemeEnd.upperBound...]
                    guard let slashIndex = afterScheme.firstIndex(of: "/") else { return false }
                    let host = String(afterScheme[afterScheme.startIndex..<slashIndex])
                    return host != "*" && !host.hasPrefix("*.")
                }

                if allDomainSpecific {
                    contentScripts[i].removeValue(forKey: "world")
                    Self.logger.info("Reverted MAIN world on [\(jsFiles.joined(separator: ", "), privacy: .public)] — restoring to ISOLATED")
                    changed = true
                }
            }
            manifest["content_scripts"] = contentScripts
        }

        // --- Add externally_connectable bridge content script ---
        if let ec = manifest["externally_connectable"] as? [String: Any],
           let matchPatterns = ec["matches"] as? [String], !matchPatterns.isEmpty {

            var contentScripts = manifest["content_scripts"] as? [[String: Any]] ?? []

            let existingBridgeIndex = contentScripts.firstIndex { entry in
                (entry["js"] as? [String])?.contains("nook_bridge.js") == true
            }

            if let bridgeIndex = existingBridgeIndex {
                var bridgeEntry = contentScripts[bridgeIndex]
                let currentAllFrames = bridgeEntry["all_frames"] as? Bool ?? false
                let currentRunAt = bridgeEntry["run_at"] as? String
                let currentMatches = bridgeEntry["matches"] as? [String] ?? []

                if currentAllFrames != true || currentRunAt != "document_start" || currentMatches != matchPatterns {
                    bridgeEntry["all_frames"] = true
                    bridgeEntry["run_at"] = "document_start"
                    bridgeEntry["matches"] = matchPatterns
                    contentScripts[bridgeIndex] = bridgeEntry
                    manifest["content_scripts"] = contentScripts
                    changed = true
                    Self.logger.info("Updated existing nook_bridge.js content script entry for all-frames document_start coverage")
                }
            } else {
                // Add bridge content script entry — runs in ISOLATED world (has browser.runtime)
                let bridgeEntry: [String: Any] = [
                    "all_frames": true,
                    "js": ["nook_bridge.js"],
                    "matches": matchPatterns,
                    "run_at": "document_start"
                ]
                contentScripts.append(bridgeEntry)
                manifest["content_scripts"] = contentScripts
                changed = true
                Self.logger.warning("Extension manifest modified: injected nook_bridge.js into \(extensionDirName, privacy: .public)")
            }

            // Always refresh bridge file to keep compatibility fixes for already-installed extensions.
            let bridgeDir = manifestURL.deletingLastPathComponent()
            let bridgeFileURL = bridgeDir.appendingPathComponent("nook_bridge.js")
            let bridgeJS = """
            // Nook: externally_connectable bridge relay
            // Runs as extension content script (ISOLATED world) with browser.runtime access.
            // Listens for postMessage from page-world polyfill and forwards to background.
            (function() {
                var runtimeAPI = null;
                try {
                    if (typeof browser !== 'undefined' && browser.runtime) {
                        runtimeAPI = browser.runtime;
                    } else if (typeof chrome !== 'undefined' && chrome.runtime) {
                        runtimeAPI = chrome.runtime;
                    }
                } catch (_) {}

                var runtimeVersion = null;
                try {
                    if (runtimeAPI && runtimeAPI.getManifest) {
                        runtimeVersion = runtimeAPI.getManifest().version || null;
                    }
                } catch (_) {}
                var bridgePorts = Object.create(null);

                function currentRuntimeId() {
                    try {
                        return runtimeAPI && runtimeAPI.id ? runtimeAPI.id : null;
                    } catch (_) {
                        return null;
                    }
                }

                function isTargetedMessage(data) {
                    if (!data || typeof data !== 'object') return false;
                    var targetRuntimeId = data.targetRuntimeId;
                    if (!targetRuntimeId || typeof targetRuntimeId !== 'string') return false;
                    var runtimeId = currentRuntimeId();
                    return !!runtimeId && targetRuntimeId === runtimeId;
                }

                function announceReady() {
                    window.postMessage({
                        type: 'nook_ec_bridge_ready',
                        targetRuntimeId: currentRuntimeId()
                    }, window.location.origin);
                }

                announceReady();
                setTimeout(announceReady, 0);
                setTimeout(announceReady, 100);
                setTimeout(announceReady, 500);

                function lastErrorMessage() {
                    try {
                        if (typeof chrome !== 'undefined' && chrome.runtime && chrome.runtime.lastError && chrome.runtime.lastError.message) {
                            return chrome.runtime.lastError.message;
                        }
                    } catch (_) {}
                    return null;
                }

                function relaySendMessage(data) {
                    if (!runtimeAPI || typeof runtimeAPI.sendMessage !== 'function') {
                        window.postMessage({
                            type: 'nook_ec_response',
                            callbackId: data.callbackId,
                            targetRuntimeId: currentRuntimeId(),
                            error: 'runtime.sendMessage unavailable'
                        }, window.location.origin);
                        return;
                    }

                    var callbackId = data.callbackId;
                    var message = data.message;
                    var options = data.options;
                    var outgoingMessage = message;

                    if (outgoingMessage && typeof outgoingMessage === 'object') {
                        // Preserve sender when provided by the page; default to page semantics.
                        outgoingMessage = Object.assign({ sender: 'page' }, outgoingMessage);
                        // Proton's broker enforces a version field for internal messages.
                        if (runtimeVersion && typeof outgoingMessage.version === 'undefined') {
                            outgoingMessage.version = runtimeVersion;
                        }
                    }

                    var outgoingType = (
                        outgoingMessage && typeof outgoingMessage === 'object' && outgoingMessage.type
                    ) ? outgoingMessage.type : typeof outgoingMessage;
                    console.log('[NOOK-EC] Relay send type=' + outgoingType + ' version=' + (
                        outgoingMessage && typeof outgoingMessage === 'object' ? (outgoingMessage.version || '(none)') : '(n/a)'
                    ));

                    var sendPromise = new Promise(function(resolve, reject) {
                        var result;
                        try {
                            if (typeof options !== 'undefined') {
                                result = runtimeAPI.sendMessage(outgoingMessage, options);
                            } else {
                                result = runtimeAPI.sendMessage(outgoingMessage);
                            }
                        } catch (error) {
                            reject(error);
                            return;
                        }
                        if (result && typeof result.then === 'function') {
                            result.then(resolve).catch(reject);
                        } else {
                            resolve(result);
                        }
                    });

                    Promise.resolve(sendPromise).then(function(response) {
                        console.log('[NOOK-EC] Relay success type=' + outgoingType);
                        window.postMessage({
                            type: 'nook_ec_response',
                            callbackId: callbackId,
                            targetRuntimeId: currentRuntimeId(),
                            response: response
                        }, window.location.origin);
                    }).catch(function(error) {
                        console.warn('[NOOK-EC] Relay error type=' + outgoingType + ': ' + ((error && error.message) ? error.message : String(error)));
                        window.postMessage({
                            type: 'nook_ec_response',
                            callbackId: callbackId,
                            targetRuntimeId: currentRuntimeId(),
                            error: (error && error.message) ? error.message : String(error)
                        }, window.location.origin);
                    });
                }

                function relayConnectOpen(data) {
                    var portId = data.portId;
                    if (!portId) return;

                    if (!runtimeAPI || typeof runtimeAPI.connect !== 'function') {
                        window.postMessage({
                            type: 'nook_ec_connect_disconnect',
                            portId: portId,
                            targetRuntimeId: currentRuntimeId(),
                            error: 'runtime.connect unavailable'
                        }, window.location.origin);
                        return;
                    }

                    var connectInfo = data.connectInfo;
                    if (!connectInfo || typeof connectInfo !== 'object') {
                        connectInfo = {};
                    }

                    console.log('[NOOK-EC] Relay connect open id=' + portId + ' name=' + (connectInfo.name || '') + ' ext=' + (data.extensionId || '(none)'));

                    var port;
                    try {
                        // Intentionally ignore external extensionId and connect internally.
                        port = runtimeAPI.connect(connectInfo);
                    } catch (error) {
                        window.postMessage({
                            type: 'nook_ec_connect_disconnect',
                            portId: portId,
                            targetRuntimeId: currentRuntimeId(),
                            error: (error && error.message) ? error.message : String(error)
                        }, window.location.origin);
                        return;
                    }

                    bridgePorts[portId] = port;
                    port.onMessage.addListener(function(message) {
                        window.postMessage({
                            type: 'nook_ec_connect_message',
                            portId: portId,
                            targetRuntimeId: currentRuntimeId(),
                            message: message
                        }, window.location.origin);
                    });
                    port.onDisconnect.addListener(function() {
                        var error = lastErrorMessage();
                        delete bridgePorts[portId];
                        console.log('[NOOK-EC] Relay connect disconnect id=' + portId + (error ? (' error=' + error) : ''));
                        window.postMessage({
                            type: 'nook_ec_connect_disconnect',
                            portId: portId,
                            targetRuntimeId: currentRuntimeId(),
                            error: error
                        }, window.location.origin);
                    });

                    window.postMessage({
                        type: 'nook_ec_connect_opened',
                        portId: portId,
                        targetRuntimeId: currentRuntimeId()
                    }, window.location.origin);
                }

                function relayConnectPost(data) {
                    var port = bridgePorts[data.portId];
                    if (!port) return;
                    try {
                        port.postMessage(data.message);
                    } catch (error) {
                        delete bridgePorts[data.portId];
                        window.postMessage({
                            type: 'nook_ec_connect_disconnect',
                            portId: data.portId,
                            targetRuntimeId: currentRuntimeId(),
                            error: (error && error.message) ? error.message : String(error)
                        }, window.location.origin);
                    }
                }

                function relayConnectClose(data) {
                    var portId = data.portId;
                    var port = bridgePorts[portId];
                    if (!port) return;
                    delete bridgePorts[portId];
                    try {
                        port.disconnect();
                    } catch (_) {}
                    window.postMessage({
                        type: 'nook_ec_connect_disconnect',
                        portId: portId,
                        targetRuntimeId: currentRuntimeId(),
                        error: null
                    }, window.location.origin);
                }

                window.addEventListener('message', function(event) {
                    if (event.source !== window) return;
                    if (event.origin !== window.location.origin) return;
                    if (!event.data || typeof event.data.type !== 'string') return;
                    if (event.data.type === 'nook_ec_request') {
                        if (!isTargetedMessage(event.data)) return;
                        relaySendMessage(event.data);
                        return;
                    }
                    if (event.data.type === 'nook_ec_connect_open') {
                        if (!isTargetedMessage(event.data)) return;
                        relayConnectOpen(event.data);
                        return;
                    }
                    if (event.data.type === 'nook_ec_connect_post') {
                        if (!isTargetedMessage(event.data)) return;
                        relayConnectPost(event.data);
                        return;
                    }
                    if (event.data.type === 'nook_ec_connect_close') {
                        if (!isTargetedMessage(event.data)) return;
                        relayConnectClose(event.data);
                        return;
                    }
                });
            })();
            """

            let existingBridgeJS = try? String(contentsOf: bridgeFileURL, encoding: .utf8)
            if existingBridgeJS != bridgeJS {
                try? bridgeJS.write(to: bridgeFileURL, atomically: true, encoding: .utf8)
                Self.logger.info("Updated nook_bridge.js for externally_connectable bridge compatibility")
                changed = true
            }

            if existingBridgeIndex == nil {
                Self.logger.info("Created nook_bridge.js and registered in manifest for externally_connectable bridge")
            }
        }

        // --- Ensure MV2 extensions have "scripting" permission ---
        // WKWebExtension exposes chrome.scripting for MV2 extensions. Some MV2 extensions
        // (like Bitwarden) detect chrome.scripting availability and prefer it over the older
        // chrome.tabs.executeScript() API. If the manifest lacks "scripting", the calls fail
        // silently and dynamic script injection (e.g. inline autofill overlay) never runs.
        let manifestVersion = manifest["manifest_version"] as? Int ?? 3
        if manifestVersion == 2 {
            var permissions = manifest["permissions"] as? [String] ?? []
            if !permissions.contains("scripting") {
                permissions.append("scripting")
                manifest["permissions"] = permissions
                changed = true
                Self.logger.warning("Extension manifest modified: added 'scripting' permission to \(extensionDirName, privacy: .public)")
            }
        }

        // --- Add Bitwarden iframe message bridge for inline menu height ---
        // Bitwarden's inline autofill menu uses an iframe that sends height updates via
        // parent.postMessage(). In WKWebExtension, content scripts run in an isolated world
        // and don't receive these messages. We inject a MAIN-world script that forwards
        // iframe messages to the isolated content script.
        let extensionId = manifestURL.deletingLastPathComponent().lastPathComponent
        let isBitwarden = (manifest["name"] as? String)?.contains("Bitwarden") == true ||
                          extensionId == "9c120cf8-9b3a-468c-9f1f-a37f29bd519c"
        if isBitwarden {
            var contentScripts = manifest["content_scripts"] as? [[String: Any]] ?? []
            let bridgeExists = contentScripts.contains { entry in
                (entry["js"] as? [String])?.contains("nook_iframe_bridge.js") == true
            }
            if !bridgeExists {
                let iframeBridgeEntry: [String: Any] = [
                    "all_frames": true,
                    "js": ["nook_iframe_bridge.js"],
                    "matches": ["<all_urls>"],
                    "run_at": "document_start",
                    "world": "MAIN"
                ]
                contentScripts.append(iframeBridgeEntry)
                manifest["content_scripts"] = contentScripts
                changed = true
                Self.logger.warning("Extension manifest modified: injected nook_iframe_bridge.js (Bitwarden special-case) into \(extensionDirName, privacy: .public)")
            }

            // Write the bridge file
            let bridgeDir = manifestURL.deletingLastPathComponent()
            let bridgeFileURL = bridgeDir.appendingPathComponent("nook_iframe_bridge.js")
            let bridgeJS = """
            // Nook: Bitwarden iframe message bridge
            // Runs in MAIN world to receive iframe postMessages and update iframe styles directly.
            (function() {
                // Find Bitwarden's autofill inline menu iframe and update its height
                function findBitwardenIframe() {
                    // The iframe is injected into a shadow DOM by Bitwarden's content script
                    // Look for iframes with webkit-extension:// src containing "overlay/menu"
                    var iframes = document.querySelectorAll('iframe');
                    for (var i = 0; i < iframes.length; i++) {
                        var iframe = iframes[i];
                        if (iframe.src && iframe.src.includes('overlay/menu') && iframe.src.includes('webkit-extension')) {
                            return iframe;
                        }
                    }
                    // Also check shadow DOM elements
                    var allElements = document.querySelectorAll('*');
                    for (var j = 0; j < allElements.length; j++) {
                        var el = allElements[j];
                        if (el.shadowRoot) {
                            var shadowIframes = el.shadowRoot.querySelectorAll('iframe');
                            for (var k = 0; k < shadowIframes.length; k++) {
                                var sIframe = shadowIframes[k];
                                if (sIframe.src && sIframe.src.includes('overlay/menu') && sIframe.src.includes('webkit-extension')) {
                                    return sIframe;
                                }
                            }
                        }
                    }
                    return null;
                }

                window.addEventListener('message', function(event) {
                    var data = event.data;
                    if (!data || typeof data !== 'object') return;
                    if (!data.command) return;

                    // Handle height update from iframe
                    if (data.command === 'updateAutofillInlineMenuListHeight' && data.styles && data.styles.height) {
                        var iframe = findBitwardenIframe();
                        if (iframe) {
                            iframe.style.height = data.styles.height;
                            iframe.style.opacity = '1';
                            iframe.style.display = 'block';
                        }
                    }
                });
            })();
            """
            let existingBridgeJS = try? String(contentsOf: bridgeFileURL, encoding: .utf8)
            if existingBridgeJS != bridgeJS {
                try? bridgeJS.write(to: bridgeFileURL, atomically: true, encoding: .utf8)
                Self.logger.info("Updated nook_iframe_bridge.js for Bitwarden iframe message forwarding")
                changed = true
            }
        }

        if changed {
            if let updatedData = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) {
                try? updatedData.write(to: manifestURL)
                Self.logger.warning("Extension manifest written to disk for \(extensionDirName, privacy: .public)")
            }
        }
    }
}
