// Phase 1 Tester - Background Service Worker
// Tests: MessagePorts (1.1), Runtime Messaging (1.2), Commands (1.3), ContextMenus (1.3)

console.log('🚀 Phase 1 Tester - Background Service Worker Started');

// =============================================================================
// TASK 1.1 TEST: MessagePort Management
// =============================================================================

let testPorts = new Map();
let portMessageCount = 0;

// Listen for port connections
chrome.runtime.onConnect.addListener((port) => {
  console.log('✅ [Task 1.1] Port connected:', port.name);
  testPorts.set(port.name, port);
  
  // Test: Send a message through the port
  port.postMessage({
    type: 'port-connection-ack',
    portName: port.name,
    timestamp: Date.now()
  });
  
  // Listen for messages on this port
  port.onMessage.addListener((msg) => {
    portMessageCount++;
    console.log(`📨 [Task 1.1] Message received on port "${port.name}":`, msg);
    
    // Echo back with additional data
    port.postMessage({
      type: 'port-echo',
      originalMessage: msg,
      messageCount: portMessageCount,
      timestamp: Date.now()
    });
  });
  
  // Handle port disconnection
  port.onDisconnect.addListener(() => {
    console.log(`❌ [Task 1.1] Port disconnected: ${port.name}`);
    testPorts.delete(port.name);
  });
});

// =============================================================================
// TASK 1.2 TEST: Runtime Message Handling with Real Responses
// =============================================================================

let runtimeMessageCount = 0;

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  runtimeMessageCount++;
  
  console.log('📬 [Task 1.2] Runtime message received:', {
    messageCount: runtimeMessageCount,
    message: message,
    sender: {
      id: sender.id,
      url: sender.url,
      tab: sender.tab?.id
    }
  });
  
  // Handle different test message types
  if (message.type === 'ping') {
    console.log('🏓 [Task 1.2] Ping received, sending pong...');
    sendResponse({
      type: 'pong',
      receivedAt: Date.now(),
      messageCount: runtimeMessageCount,
      originalMessage: message
    });
    return true; // Keep channel open for async response
  }
  
  if (message.type === 'get-data') {
    console.log('📊 [Task 1.2] Data request received, fetching...');
    
    // Simulate async data fetch
    setTimeout(() => {
      sendResponse({
        type: 'data-response',
        data: {
          testValue: 'Phase 1 is working!',
          timestamp: Date.now(),
          messageCount: runtimeMessageCount,
          randomValue: Math.random()
        },
        success: true
      });
    }, 100);
    
    return true; // Keep channel open for async response
  }
  
  if (message.type === 'store-test') {
    console.log('💾 [Task 1.2] Storage test requested...');
    
    // Test storage integration
    chrome.storage.local.set({
      testData: message.data,
      lastUpdated: Date.now()
    }, () => {
      chrome.storage.local.get(['testData', 'lastUpdated'], (result) => {
        sendResponse({
          type: 'storage-result',
          stored: result,
          success: true
        });
      });
    });
    
    return true; // Keep channel open for async response
  }
  
  if (message.type === 'round-trip-test') {
    console.log('🔄 [Task 1.2] Round-trip test initiated...');
    
    // Complex multi-step test
    const startTime = Date.now();
    
    chrome.storage.local.set({
      roundTripTest: {
        startTime: startTime,
        data: message.data
      }
    }, () => {
      chrome.storage.local.get(['roundTripTest'], (result) => {
        sendResponse({
          type: 'round-trip-result',
          success: true,
          latency: Date.now() - startTime,
          data: result.roundTripTest,
          messageCount: runtimeMessageCount
        });
      });
    });
    
    return true;
  }
  
  // Default response for unknown message types
  console.log('❓ [Task 1.2] Unknown message type, sending default response');
  sendResponse({
    type: 'unknown',
    receivedMessage: message,
    timestamp: Date.now()
  });
  
  return true;
});

// =============================================================================
// TASK 1.3 TEST: Commands Event Delivery
// =============================================================================

let commandTriggerCount = 0;

chrome.commands.onCommand.addListener((command) => {
  commandTriggerCount++;
  
  console.log('⌨️ [Task 1.3] Command triggered:', {
    command: command,
    triggerCount: commandTriggerCount,
    timestamp: Date.now()
  });
  
  // Store command trigger in storage for popup to read
  chrome.storage.local.get(['commandHistory'], (result) => {
    const history = result.commandHistory || [];
    history.push({
      command: command,
      timestamp: Date.now(),
      triggerCount: commandTriggerCount
    });
    
    // Keep only last 10
    if (history.length > 10) {
      history.shift();
    }
    
    chrome.storage.local.set({ commandHistory: history }, () => {
      console.log('✅ [Task 1.3] Command history updated');
    });
  });
  
  // Test: Send message to all connected ports
  testPorts.forEach((port, name) => {
    console.log(`📤 [Task 1.3] Broadcasting command to port: ${name}`);
    port.postMessage({
      type: 'command-triggered',
      command: command,
      timestamp: Date.now()
    });
  });
  
  // Create a notification via console
  console.log(`🎯 [Task 1.3] Command "${command}" executed successfully!`);
});

// =============================================================================
// TASK 1.3 TEST: Context Menu Event Delivery
// =============================================================================

let contextMenuClickCount = 0;

// Create context menu items
chrome.runtime.onInstalled.addListener(() => {
  console.log('🔧 [Setup] Creating context menu items...');
  
  chrome.contextMenus.create({
    id: 'test-menu-1',
    title: 'Test Menu Item 1 - Simple Click',
    contexts: ['page', 'selection']
  }, () => {
    if (chrome.runtime.lastError) {
      console.error('❌ [Setup] Error creating menu 1:', chrome.runtime.lastError);
    } else {
      console.log('✅ [Setup] Context menu 1 created');
    }
  });
  
  chrome.contextMenus.create({
    id: 'test-menu-2',
    title: 'Test Menu Item 2 - With Data',
    contexts: ['page', 'link', 'image']
  }, () => {
    if (chrome.runtime.lastError) {
      console.error('❌ [Setup] Error creating menu 2:', chrome.runtime.lastError);
    } else {
      console.log('✅ [Setup] Context menu 2 created');
    }
  });
  
  chrome.contextMenus.create({
    id: 'test-submenu',
    title: 'Test Submenu',
    contexts: ['page']
  }, () => {
    chrome.contextMenus.create({
      id: 'test-submenu-item-1',
      parentId: 'test-submenu',
      title: 'Submenu Item 1',
      contexts: ['page']
    }, () => {
      if (chrome.runtime.lastError) {
        console.error('❌ [Setup] Error creating submenu:', chrome.runtime.lastError);
      } else {
        console.log('✅ [Setup] Submenu created');
      }
    });
  });
});

chrome.contextMenus.onClicked.addListener((info, tab) => {
  contextMenuClickCount++;
  
  console.log('🖱️ [Task 1.3] Context menu clicked:', {
    menuItemId: info.menuItemId,
    clickCount: contextMenuClickCount,
    pageUrl: info.pageUrl,
    linkUrl: info.linkUrl,
    srcUrl: info.srcUrl,
    selectionText: info.selectionText,
    tabId: tab?.id,
    timestamp: Date.now()
  });
  
  // Store click event for popup to read
  chrome.storage.local.get(['menuClickHistory'], (result) => {
    const history = result.menuClickHistory || [];
    history.push({
      menuItemId: info.menuItemId,
      pageUrl: info.pageUrl,
      timestamp: Date.now(),
      clickCount: contextMenuClickCount
    });
    
    // Keep only last 10
    if (history.length > 10) {
      history.shift();
    }
    
    chrome.storage.local.set({ menuClickHistory: history }, () => {
      console.log('✅ [Task 1.3] Menu click history updated');
    });
  });
  
  // Broadcast to all ports
  testPorts.forEach((port, name) => {
    port.postMessage({
      type: 'menu-clicked',
      menuItemId: info.menuItemId,
      pageUrl: info.pageUrl,
      timestamp: Date.now()
    });
  });
  
  console.log(`🎯 [Task 1.3] Context menu "${info.menuItemId}" handled successfully!`);
});

// =============================================================================
// STATUS REPORTING
// =============================================================================

// Expose status via runtime message
setInterval(() => {
  const status = {
    ports: {
      count: testPorts.size,
      names: Array.from(testPorts.keys()),
      totalMessages: portMessageCount
    },
    runtimeMessages: {
      count: runtimeMessageCount
    },
    commands: {
      triggerCount: commandTriggerCount
    },
    contextMenus: {
      clickCount: contextMenuClickCount
    },
    uptime: Date.now()
  };
  
  // Store current status
  chrome.storage.local.set({ backgroundStatus: status });
}, 1000);

console.log('✅ Phase 1 Tester - Background Service Worker Ready');
console.log('📋 Available Tests:');
console.log('  - Task 1.1: Connect ports and send messages');
console.log('  - Task 1.2: Send runtime messages (ping, get-data, store-test, round-trip-test)');
console.log('  - Task 1.3: Trigger keyboard commands (Cmd+Shift+1/2/3)');
console.log('  - Task 1.3: Click context menu items (right-click on page)');

