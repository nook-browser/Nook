// Phase 1 Tester - Content Script
// Tests content script injection and messaging capabilities

console.log('🌐 Phase 1 Tester - Content Script Loaded on:', window.location.href);

// Create a visual indicator that the extension is active
function createIndicator() {
  const indicator = document.createElement('div');
  indicator.id = 'phase1-tester-indicator';
  indicator.style.cssText = `
    position: fixed;
    top: 10px;
    right: 10px;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 12px 16px;
    border-radius: 8px;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    font-size: 14px;
    font-weight: 600;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
    z-index: 999999;
    cursor: pointer;
    transition: all 0.3s ease;
  `;
  indicator.innerHTML = '🧪 Phase 1 Tester Active';
  
  // Add hover effect
  indicator.addEventListener('mouseenter', () => {
    indicator.style.transform = 'scale(1.05)';
  });
  
  indicator.addEventListener('mouseleave', () => {
    indicator.style.transform = 'scale(1)';
  });
  
  // Click to test messaging
  indicator.addEventListener('click', () => {
    testContentScriptMessaging();
  });
  
  document.body.appendChild(indicator);
  
  // Auto-hide after 5 seconds
  setTimeout(() => {
    indicator.style.opacity = '0.3';
    indicator.style.transform = 'scale(0.9)';
  }, 5000);
  
  // Show on hover
  indicator.addEventListener('mouseenter', () => {
    indicator.style.opacity = '1';
    indicator.style.transform = 'scale(1.05)';
  });
}

// Test content script to background messaging
function testContentScriptMessaging() {
  console.log('📤 Content script testing runtime.sendMessage...');
  
  chrome.runtime.sendMessage({
    type: 'content-script-test',
    url: window.location.href,
    timestamp: Date.now(),
    test: 'Phase 1 content script messaging'
  }, (response) => {
    if (chrome.runtime.lastError) {
      console.error('❌ Content script message error:', chrome.runtime.lastError);
      showNotification('❌ Message Failed', 'error');
      return;
    }
    
    console.log('✅ Content script received response:', response);
    showNotification('✅ Message Sent Successfully!', 'success');
  });
}

// Show notification
function showNotification(message, type) {
  const notification = document.createElement('div');
  notification.style.cssText = `
    position: fixed;
    top: 80px;
    right: 10px;
    background: ${type === 'success' ? '#10b981' : '#ef4444'};
    color: white;
    padding: 12px 16px;
    border-radius: 8px;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    font-size: 14px;
    font-weight: 500;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.15);
    z-index: 999999;
    animation: slideIn 0.3s ease;
  `;
  notification.textContent = message;
  
  document.body.appendChild(notification);
  
  setTimeout(() => {
    notification.style.animation = 'slideOut 0.3s ease';
    setTimeout(() => notification.remove(), 300);
  }, 3000);
}

// Listen for messages from background
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('📬 Content script received message:', message);
  
  if (message.type === 'ping-content') {
    console.log('🏓 Ping received from background');
    sendResponse({
      type: 'pong-content',
      url: window.location.href,
      timestamp: Date.now()
    });
    showNotification('🏓 Ping from Background!', 'success');
  }
  
  if (message.type === 'command-triggered') {
    console.log(`⌨️ Command "${message.command}" triggered in background`);
    showNotification(`⌨️ Command: ${message.command}`, 'success');
  }
  
  if (message.type === 'menu-clicked') {
    console.log(`🖱️ Menu "${message.menuItemId}" clicked in background`);
    showNotification(`🖱️ Menu: ${message.menuItemId}`, 'success');
  }
  
  return true;
});

// Try to establish a port connection (test Task 1.1 from content script)
try {
  const contentPort = chrome.runtime.connect({ name: 'content-script-port' });
  
  contentPort.onMessage.addListener((msg) => {
    console.log('📨 Content script received port message:', msg);
    
    // Show notification for certain message types
    if (msg.type === 'command-triggered' || msg.type === 'menu-clicked') {
      const emoji = msg.type === 'command-triggered' ? '⌨️' : '🖱️';
      const label = msg.type === 'command-triggered' ? msg.command : msg.menuItemId;
      showNotification(`${emoji} ${label}`, 'success');
    }
  });
  
  contentPort.onDisconnect.addListener(() => {
    console.log('❌ Content script port disconnected');
  });
  
  console.log('✅ Content script port connected');
  
  // Send initial message
  contentPort.postMessage({
    type: 'content-script-connected',
    url: window.location.href,
    timestamp: Date.now()
  });
  
} catch (error) {
  console.error('❌ Error connecting content script port:', error);
}

// Initialize
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', createIndicator);
} else {
  createIndicator();
}

console.log('✅ Phase 1 Tester - Content Script Ready');

