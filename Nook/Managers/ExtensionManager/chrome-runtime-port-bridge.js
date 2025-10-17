// Chrome Runtime Port Bridge
// Implements chrome.runtime.connect() Port object for WebExtension compatibility
// This file is injected into web pages by ExtensionManager+Runtime.swift

(function() {
    'use strict';
    
    // Create Port factory function
    window.createChromeRuntimePort = function(extensionId, extensionIdOrConnectInfo, connectInfo) {
        // Parse arguments (supports both connect() and connect(extensionId, connectInfo))
        let targetExtensionId = null;
        let portName = null;
        
        if (typeof extensionIdOrConnectInfo === 'string') {
            // Called as connect(extensionId, connectInfo)
            targetExtensionId = extensionIdOrConnectInfo;
            portName = connectInfo?.name || null;
        } else if (typeof extensionIdOrConnectInfo === 'object') {
            // Called as connect(connectInfo)
            portName = extensionIdOrConnectInfo?.name || null;
        } else {
            // Called as connect() with no args
            portName = null;
        }
        
        // Generate unique port ID
        const portId = 'port_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
        
        // Create Port object
        const port = {
            name: portName || '',
            sender: {
                id: extensionId,
                url: 'webkit-extension://' + extensionId + '/',
                tab: null
            },
            _portId: portId,
            _disconnected: false,
            _onMessageListeners: [],
            _onDisconnectListeners: [],
            
            // onMessage event API
            onMessage: {
                addListener: function(listener) {
                    if (typeof listener === 'function') {
                        port._onMessageListeners.push(listener);
                    }
                },
                removeListener: function(listener) {
                    const index = port._onMessageListeners.indexOf(listener);
                    if (index > -1) {
                        port._onMessageListeners.splice(index, 1);
                    }
                },
                hasListener: function(listener) {
                    return port._onMessageListeners.indexOf(listener) > -1;
                }
            },
            
            // onDisconnect event API
            onDisconnect: {
                addListener: function(listener) {
                    if (typeof listener === 'function') {
                        port._onDisconnectListeners.push(listener);
                    }
                },
                removeListener: function(listener) {
                    const index = port._onDisconnectListeners.indexOf(listener);
                    if (index > -1) {
                        port._onDisconnectListeners.splice(index, 1);
                    }
                },
                hasListener: function(listener) {
                    return port._onDisconnectListeners.indexOf(listener) > -1;
                }
            },
            
            // postMessage method
            postMessage: function(message) {
                if (port._disconnected) {
                    console.error('[Port] Cannot post message on disconnected port:', portName);
                    return;
                }
                
                try {
                    const messageData = {
                        type: 'portMessage',
                        portId: portId,
                        portName: portName,
                        message: message,
                        timestamp: Date.now().toString()
                    };
                    
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chromeRuntime) {
                        window.webkit.messageHandlers.chromeRuntime.postMessage(messageData);
                    } else {
                        console.error('[Port] chromeRuntime message handler not available');
                    }
                } catch (error) {
                    console.error('[Port] postMessage error:', error.message);
                }
            },
            
            // disconnect method
            disconnect: function() {
                if (port._disconnected) {
                    return;
                }
                
                port._disconnected = true;
                
                try {
                    // Notify native side
                    const messageData = {
                        type: 'portDisconnect',
                        portId: portId,
                        portName: portName,
                        timestamp: Date.now().toString()
                    };
                    
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chromeRuntime) {
                        window.webkit.messageHandlers.chromeRuntime.postMessage(messageData);
                    }
                    
                    // Fire onDisconnect listeners
                    port._onDisconnectListeners.forEach(function(listener) {
                        try {
                            listener(port);
                        } catch (error) {
                            console.error('[Port] onDisconnect listener error:', error.message);
                        }
                    });
                    
                    // Cleanup
                    port._onMessageListeners = [];
                    port._onDisconnectListeners = [];
                    
                    // Remove from global port registry
                    if (window.chromeRuntimePorts) {
                        delete window.chromeRuntimePorts[portId];
                    }
                } catch (error) {
                    console.error('[Port] disconnect error:', error.message);
                }
            },
            
            // Internal method to receive messages
            _receiveMessage: function(message) {
                if (port._disconnected) {
                    return;
                }
                
                port._onMessageListeners.forEach(function(listener) {
                    try {
                        listener(message, port);
                    } catch (error) {
                        console.error('[Port] onMessage listener error:', error.message);
                    }
                });
            },
            
            // Internal method to handle disconnect from native side
            _handleDisconnect: function(error) {
                if (port._disconnected) {
                    return;
                }
                
                port._disconnected = true;
                
                if (error) {
                    port.error = { message: error };
                }
                
                port._onDisconnectListeners.forEach(function(listener) {
                    try {
                        listener(port);
                    } catch (error) {
                        console.error('[Port] onDisconnect listener error:', error.message);
                    }
                });
                
                // Cleanup
                port._onMessageListeners = [];
                port._onDisconnectListeners = [];
                
                // Remove from global port registry
                if (window.chromeRuntimePorts) {
                    delete window.chromeRuntimePorts[portId];
                }
            }
        };
        
        // Store port in global registry for native callbacks
        if (!window.chromeRuntimePorts) {
            window.chromeRuntimePorts = {};
        }
        window.chromeRuntimePorts[portId] = port;
        
        // Notify native side about port connection
        const connectMessage = {
            type: 'portConnect',
            portId: portId,
            portName: portName,
            extensionId: targetExtensionId,
            timestamp: Date.now().toString()
        };
        
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.chromeRuntime) {
            window.webkit.messageHandlers.chromeRuntime.postMessage(connectMessage);
        }
        
        console.log('[Port] Created port:', portId, 'name:', portName);
        
        return port;
    };
    
    console.log('[Chrome Runtime Port Bridge] Port factory loaded');
})();

