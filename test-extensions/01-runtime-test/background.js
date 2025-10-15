/**
 * Runtime API Test - Background Script
 * Tests chrome.runtime.* APIs
 */

console.log('🚀 [Runtime Test] Background script starting...');

// Test 1: chrome.runtime.id
function testRuntimeId() {
  console.log('✅ Test 1: chrome.runtime.id');
  console.log('   Extension ID:', chrome.runtime.id);
  if (chrome.runtime.id) {
    console.log('   ✅ PASS: runtime.id is available');
  } else {
    console.error('   ❌ FAIL: runtime.id is missing');
  }
}

// Test 2: chrome.runtime.getManifest()
function testGetManifest() {
  console.log('✅ Test 2: chrome.runtime.getManifest()');
  try {
    const manifest = chrome.runtime.getManifest();
    console.log('   Manifest:', manifest);
    if (manifest && manifest.name === 'Runtime API Test') {
      console.log('   ✅ PASS: getManifest() works correctly');
    } else {
      console.error('   ❌ FAIL: getManifest() returned unexpected data');
    }
  } catch (error) {
    console.error('   ❌ FAIL: getManifest() threw error:', error);
  }
}

// Test 3: chrome.runtime.getURL()
function testGetURL() {
  console.log('✅ Test 3: chrome.runtime.getURL()');
  try {
    const url = chrome.runtime.getURL('popup.html');
    console.log('   URL:', url);
    if (url && url.includes('popup.html')) {
      console.log('   ✅ PASS: getURL() works correctly');
    } else {
      console.error('   ❌ FAIL: getURL() returned unexpected URL');
    }
  } catch (error) {
    console.error('   ❌ FAIL: getURL() threw error:', error);
  }
}

// Test 4: chrome.runtime.sendMessage() from background to popup
function testSendMessage() {
  console.log('✅ Test 4: chrome.runtime.sendMessage()');
  try {
    chrome.runtime.sendMessage(
      { type: 'PING', from: 'background' },
      (response) => {
        if (chrome.runtime.lastError) {
          console.error('   ❌ FAIL: sendMessage error:', chrome.runtime.lastError.message);
        } else if (response) {
          console.log('   Response:', response);
          console.log('   ✅ PASS: sendMessage() works correctly');
        } else {
          console.warn('   ⚠️  WARN: No response received (popup may not be open)');
        }
      }
    );
  } catch (error) {
    console.error('   ❌ FAIL: sendMessage() threw error:', error);
  }
}

// Test 5: chrome.runtime.onMessage listener
function testOnMessageListener() {
  console.log('✅ Test 5: chrome.runtime.onMessage listener');
  try {
    chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
      console.log('   Received message:', message);
      console.log('   From:', sender);
      
      if (message.type === 'PING') {
        console.log('   ✅ PASS: onMessage listener works correctly');
        sendResponse({ type: 'PONG', from: 'background', timestamp: Date.now() });
        return true; // Keep channel open for async response
      }
      
      if (message.type === 'TEST_RESPONSE') {
        console.log('   ✅ Response from content script received');
      }
    });
    console.log('   ✅ Message listener registered');
  } catch (error) {
    console.error('   ❌ FAIL: onMessage.addListener() threw error:', error);
  }
}

// Test 6: chrome.runtime.onInstalled
function testOnInstalled() {
  console.log('✅ Test 6: chrome.runtime.onInstalled listener');
  try {
    chrome.runtime.onInstalled.addListener((details) => {
      console.log('   onInstalled event:', details);
      console.log('   Reason:', details.reason);
      console.log('   ✅ PASS: onInstalled listener works correctly');
    });
    console.log('   ✅ onInstalled listener registered');
  } catch (error) {
    console.error('   ❌ FAIL: onInstalled.addListener() threw error:', error);
  }
}

// Test 7: chrome.runtime.onStartup
function testOnStartup() {
  console.log('✅ Test 7: chrome.runtime.onStartup listener');
  try {
    chrome.runtime.onStartup.addListener(() => {
      console.log('   onStartup event fired');
      console.log('   ✅ PASS: onStartup listener works correctly');
    });
    console.log('   ✅ onStartup listener registered');
  } catch (error) {
    console.error('   ❌ FAIL: onStartup.addListener() threw error:', error);
  }
}

// Test 8: Message to content script
function testMessageToContentScript() {
  console.log('✅ Test 8: Message to content script via tabs.query');
  
  try {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (tabs.length > 0) {
        const tabId = tabs[0].id;
        console.log('   Sending message to tab:', tabId);
        
        chrome.tabs.sendMessage(
          tabId,
          { type: 'PING_FROM_BG', timestamp: Date.now() },
          (response) => {
            if (chrome.runtime.lastError) {
              console.warn('   ⚠️  Content script may not be loaded yet:', chrome.runtime.lastError.message);
            } else if (response) {
              console.log('   Response from content script:', response);
              console.log('   ✅ PASS: Background -> Content messaging works');
            }
          }
        );
      }
    });
  } catch (error) {
    console.error('   ❌ FAIL: Message to content script failed:', error);
  }
}

// Test 9: Rapid fire messages (stress test)
function testRapidMessages() {
  console.log('✅ Test 9: Rapid fire messages (10 messages)');
  let successCount = 0;
  let errorCount = 0;
  
  for (let i = 0; i < 10; i++) {
    try {
      chrome.runtime.sendMessage(
        { type: 'RAPID_TEST', index: i },
        (response) => {
          if (chrome.runtime.lastError) {
            errorCount++;
          } else {
            successCount++;
          }
          
          if (successCount + errorCount === 10) {
            console.log(`   Results: ${successCount}/10 successful, ${errorCount}/10 errors`);
            if (successCount >= 8) {
              console.log('   ✅ PASS: Rapid messaging works (>80% success rate)');
            } else {
              console.error('   ❌ FAIL: Too many message failures');
            }
          }
        }
      );
    } catch (error) {
      errorCount++;
      console.error('   Message', i, 'threw error:', error);
    }
  }
}

// Run all tests
function runAllTests() {
  console.log('\n=== RUNTIME API TEST SUITE ===\n');
  
  testRuntimeId();
  testGetManifest();
  testGetURL();
  testOnMessageListener();
  testOnInstalled();
  testOnStartup();
  
  // Delay tests that depend on other contexts
  setTimeout(() => {
    testSendMessage();
    testMessageToContentScript();
    testRapidMessages();
  }, 1000);
  
  console.log('\n=== TEST SUITE COMPLETE ===\n');
  console.log('Check console for results. Tests with async responses may take a moment.');
}

// Start tests when background script loads
runAllTests();

console.log('🚀 [Runtime Test] Background script ready');

