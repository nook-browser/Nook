// Phase 1 Tester - Popup Script

console.log('🎨 Phase 1 Tester - Popup Loaded');

// =============================================================================
// STATE
// =============================================================================

let currentPort = null;
let portMessagesSent = 0;
let runtimeMessagesSent = 0;
let runtimeResponsesReceived = 0;

// =============================================================================
// UTILITY FUNCTIONS
// =============================================================================

function log(elementId, message, type = 'info') {
  const resultDiv = document.getElementById(elementId);
  const entry = document.createElement('div');
  entry.className = `log-entry ${type}`;
  
  const timestamp = new Date().toLocaleTimeString();
  entry.innerHTML = `<span class="timestamp">[${timestamp}]</span> ${message}`;
  
  resultDiv.appendChild(entry);
  resultDiv.scrollTop = resultDiv.scrollHeight;
}

function clearLog(elementId) {
  document.getElementById(elementId).innerHTML = '';
}

function updateStatus(taskId, status) {
  const badge = document.getElementById(`${taskId}-status`);
  badge.textContent = status;
  badge.className = 'status-badge';
  
  if (status === 'Pass' || status === 'Active') {
    badge.classList.add('success');
  } else if (status === 'Pending' || status === 'Testing') {
    badge.classList.add('warning');
  } else if (status === 'Fail') {
    badge.classList.add('error');
  }
}

function updateStat(statId, value) {
  document.getElementById(statId).textContent = value;
}

// =============================================================================
// TASK 1.1: MessagePort Tests
// =============================================================================

document.getElementById('connect-port-btn').addEventListener('click', () => {
  console.log('🔌 Connecting port...');
  log('port-result', 'Attempting to connect port...', 'info');
  
  try {
    currentPort = chrome.runtime.connect({ name: 'popup-test-port' });
    
    currentPort.onMessage.addListener((msg) => {
      console.log('📨 Message received on port:', msg);
      log('port-result', `✅ Received: ${JSON.stringify(msg, null, 2)}`, 'success');
      updateStatus('task11', 'Pass');
    });
    
    currentPort.onDisconnect.addListener(() => {
      console.log('❌ Port disconnected');
      log('port-result', '❌ Port disconnected', 'error');
      currentPort = null;
      document.getElementById('send-port-message-btn').disabled = true;
      document.getElementById('disconnect-port-btn').disabled = true;
      document.getElementById('connect-port-btn').disabled = false;
      updateStat('port-count', 0);
      updateStatus('task11', 'Pending');
    });
    
    log('port-result', '✅ Port connected successfully!', 'success');
    document.getElementById('send-port-message-btn').disabled = false;
    document.getElementById('disconnect-port-btn').disabled = false;
    document.getElementById('connect-port-btn').disabled = true;
    updateStat('port-count', 1);
    updateStatus('task11', 'Active');
    
  } catch (error) {
    console.error('❌ Port connection error:', error);
    log('port-result', `❌ Error: ${error.message}`, 'error');
    updateStatus('task11', 'Fail');
  }
});

document.getElementById('send-port-message-btn').addEventListener('click', () => {
  if (!currentPort) {
    log('port-result', '❌ No active port connection', 'error');
    return;
  }
  
  portMessagesSent++;
  const testMessage = {
    type: 'test-message',
    data: `Test message #${portMessagesSent}`,
    timestamp: Date.now()
  };
  
  console.log('📤 Sending message through port:', testMessage);
  log('port-result', `📤 Sending: ${JSON.stringify(testMessage, null, 2)}`, 'info');
  
  try {
    currentPort.postMessage(testMessage);
    updateStat('port-messages', portMessagesSent);
  } catch (error) {
    console.error('❌ Error sending port message:', error);
    log('port-result', `❌ Error: ${error.message}`, 'error');
  }
});

document.getElementById('disconnect-port-btn').addEventListener('click', () => {
  if (!currentPort) {
    log('port-result', '❌ No active port to disconnect', 'error');
    return;
  }
  
  console.log('🔌 Disconnecting port...');
  log('port-result', 'Disconnecting port...', 'info');
  currentPort.disconnect();
});

// =============================================================================
// TASK 1.2: Runtime Message Tests
// =============================================================================

function sendRuntimeMessage(message, description) {
  runtimeMessagesSent++;
  updateStat('runtime-sent', runtimeMessagesSent);
  
  console.log(`📤 Sending runtime message: ${description}`, message);
  log('runtime-result', `📤 ${description}: ${JSON.stringify(message, null, 2)}`, 'info');
  updateStatus('task12', 'Testing');
  
  const startTime = Date.now();
  
  chrome.runtime.sendMessage(message, (response) => {
    const latency = Date.now() - startTime;
    
    if (chrome.runtime.lastError) {
      console.error('❌ Runtime message error:', chrome.runtime.lastError);
      log('runtime-result', `❌ Error: ${chrome.runtime.lastError.message}`, 'error');
      updateStatus('task12', 'Fail');
      return;
    }
    
    runtimeResponsesReceived++;
    updateStat('runtime-received', runtimeResponsesReceived);
    
    console.log(`✅ Response received (${latency}ms):`, response);
    log('runtime-result', `✅ Response (${latency}ms): ${JSON.stringify(response, null, 2)}`, 'success');
    
    // Check if response is real or synthetic
    if (response && typeof response === 'object' && Object.keys(response).length === 1 && response.success === true) {
      log('runtime-result', '⚠️ WARNING: Received synthetic success response (Task 1.2 may not be fully working)', 'error');
      updateStatus('task12', 'Fail');
    } else {
      updateStatus('task12', 'Pass');
    }
  });
}

document.getElementById('ping-btn').addEventListener('click', () => {
  sendRuntimeMessage({ type: 'ping', timestamp: Date.now() }, 'Ping');
});

document.getElementById('get-data-btn').addEventListener('click', () => {
  sendRuntimeMessage({ type: 'get-data', requestId: Date.now() }, 'Get Data');
});

document.getElementById('store-test-btn').addEventListener('click', () => {
  sendRuntimeMessage({
    type: 'store-test',
    data: {
      testValue: 'Phase 1 Storage Test',
      timestamp: Date.now(),
      random: Math.random()
    }
  }, 'Storage Test');
});

document.getElementById('round-trip-btn').addEventListener('click', () => {
  sendRuntimeMessage({
    type: 'round-trip-test',
    data: {
      initiator: 'popup',
      testId: Date.now(),
      payload: 'Complex round-trip test data'
    }
  }, 'Round Trip Test');
});

// =============================================================================
// TASK 1.3: Commands Tests
// =============================================================================

function refreshCommandHistory() {
  chrome.storage.local.get(['commandHistory'], (result) => {
    const history = result.commandHistory || [];
    
    if (history.length === 0) {
      log('commands-result', 'No commands triggered yet. Try pressing Cmd+Shift+1/2/3', 'info');
      return;
    }
    
    clearLog('commands-result');
    updateStat('command-count', history[history.length - 1]?.triggerCount || 0);
    updateStat('last-command', history[history.length - 1]?.command || 'None');
    updateStatus('task13a', 'Pass');
    
    history.forEach(entry => {
      const timestamp = new Date(entry.timestamp).toLocaleTimeString();
      log('commands-result', 
        `⌨️ "${entry.command}" at ${timestamp} (Trigger #${entry.triggerCount})`, 
        'success');
    });
  });
}

document.getElementById('refresh-commands-btn').addEventListener('click', refreshCommandHistory);

// Auto-refresh command history every 2 seconds
setInterval(refreshCommandHistory, 2000);

// =============================================================================
// TASK 1.3: Context Menu Tests
// =============================================================================

function refreshMenuHistory() {
  chrome.storage.local.get(['menuClickHistory'], (result) => {
    const history = result.menuClickHistory || [];
    
    if (history.length === 0) {
      log('menu-result', 'No menu items clicked yet. Right-click on a page and select a test menu item.', 'info');
      return;
    }
    
    clearLog('menu-result');
    updateStat('menu-count', history[history.length - 1]?.clickCount || 0);
    updateStat('last-menu', history[history.length - 1]?.menuItemId || 'None');
    updateStatus('task13b', 'Pass');
    
    history.forEach(entry => {
      const timestamp = new Date(entry.timestamp).toLocaleTimeString();
      const url = entry.pageUrl?.substring(0, 40) || 'N/A';
      log('menu-result', 
        `🖱️ "${entry.menuItemId}" at ${timestamp} on ${url}... (Click #${entry.clickCount})`, 
        'success');
    });
  });
}

document.getElementById('refresh-menu-btn').addEventListener('click', refreshMenuHistory);

document.getElementById('clear-menu-btn').addEventListener('click', () => {
  chrome.storage.local.set({ menuClickHistory: [] }, () => {
    clearLog('menu-result');
    updateStat('menu-count', 0);
    updateStat('last-menu', 'None');
    updateStatus('task13b', 'Pending');
    log('menu-result', 'Menu history cleared', 'info');
  });
});

// Auto-refresh menu history every 2 seconds
setInterval(refreshMenuHistory, 2000);

// =============================================================================
// INITIALIZATION
// =============================================================================

// Load initial state
document.addEventListener('DOMContentLoaded', () => {
  console.log('📋 Initializing popup...');
  refreshCommandHistory();
  refreshMenuHistory();
  
  // Check background status
  chrome.storage.local.get(['backgroundStatus'], (result) => {
    if (result.backgroundStatus) {
      console.log('✅ Background service worker is active:', result.backgroundStatus);
      log('runtime-result', '✅ Background service worker is active', 'success');
    } else {
      console.log('⚠️ Background status not available yet');
      log('runtime-result', '⚠️ Background status not available yet', 'info');
    }
  });
});

console.log('✅ Popup script loaded successfully');

