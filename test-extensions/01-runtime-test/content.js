/**
 * Runtime API Test - Content Script
 * Tests chrome.runtime.* APIs from content script context
 */

console.log('📄 [Runtime Test] Content script loaded on:', window.location.href);

// Test: chrome.runtime.id availability in content script
console.log('✅ Test: chrome.runtime.id in content script');
console.log('   Extension ID:', chrome.runtime.id);

// Test: Listen for messages from background script
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('📥 [Content] Received message:', message);
  console.log('   From:', sender);
  
  if (message.type === 'PING_FROM_BG') {
    console.log('   ✅ Content script received message from background');
    sendResponse({
      type: 'PONG_FROM_CONTENT',
      receivedAt: Date.now(),
      url: window.location.href
    });
    return true;
  }
});

// Test: Send message to background script
function testSendToBackground() {
  console.log('✅ Test: Send message from content to background');
  
  chrome.runtime.sendMessage(
    { type: 'TEST_RESPONSE', from: 'content', url: window.location.href },
    (response) => {
      if (chrome.runtime.lastError) {
        console.error('   ❌ Error sending to background:', chrome.runtime.lastError.message);
      } else {
        console.log('   ✅ Response from background:', response);
      }
    }
  );
}

// Test: chrome.runtime.getURL() in content script
function testGetURLInContent() {
  console.log('✅ Test: chrome.runtime.getURL() in content script');
  try {
    const url = chrome.runtime.getURL('icon48.png');
    console.log('   URL:', url);
    if (url && url.includes('icon48.png')) {
      console.log('   ✅ PASS: getURL() works in content script');
    } else {
      console.error('   ❌ FAIL: getURL() returned unexpected value');
    }
  } catch (error) {
    console.error('   ❌ FAIL: getURL() threw error:', error);
  }
}

// Run content script tests
setTimeout(() => {
  testSendToBackground();
  testGetURLInContent();
}, 500);

console.log('📄 [Runtime Test] Content script ready');

