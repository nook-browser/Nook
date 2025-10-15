/**
 * Runtime API Test - Popup Script
 * Tests chrome.runtime.* APIs from popup context
 */

console.log('🎨 [Runtime Test] Popup script loaded');

// Listen for messages from background
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('🎨 [Popup] Received message:', message);
  
  if (message.type === 'PING') {
    console.log('   ✅ Popup received message from background');
    sendResponse({ type: 'PONG', from: 'popup' });
    return true;
  }
  
  if (message.type === 'RAPID_TEST') {
    sendResponse({ type: 'RAPID_RESPONSE', index: message.index });
    return true;
  }
});

// Test runtime.id
document.getElementById('testId').addEventListener('click', () => {
  const resultDiv = document.getElementById('basicResults');
  resultDiv.style.display = 'block';
  
  console.log('✅ [Popup] Testing runtime.id');
  
  if (chrome.runtime.id) {
    resultDiv.className = 'result success';
    resultDiv.textContent = `✅ SUCCESS\nExtension ID: ${chrome.runtime.id}`;
    console.log('   ✅ PASS: runtime.id available in popup');
  } else {
    resultDiv.className = 'result error';
    resultDiv.textContent = '❌ FAIL\nruntime.id is undefined';
    console.error('   ❌ FAIL: runtime.id not available');
  }
});

// Test getManifest()
document.getElementById('testManifest').addEventListener('click', () => {
  const resultDiv = document.getElementById('basicResults');
  resultDiv.style.display = 'block';
  
  console.log('✅ [Popup] Testing getManifest()');
  
  try {
    const manifest = chrome.runtime.getManifest();
    if (manifest && manifest.name) {
      resultDiv.className = 'result success';
      resultDiv.textContent = `✅ SUCCESS\nManifest:\n${JSON.stringify(manifest, null, 2)}`;
      console.log('   ✅ PASS: getManifest() works in popup');
      console.log('   Manifest:', manifest);
    } else {
      resultDiv.className = 'result error';
      resultDiv.textContent = '❌ FAIL\ngetManifest() returned invalid data';
      console.error('   ❌ FAIL: Invalid manifest data');
    }
  } catch (error) {
    resultDiv.className = 'result error';
    resultDiv.textContent = `❌ ERROR\n${error.message}`;
    console.error('   ❌ FAIL: getManifest() threw error:', error);
  }
});

// Test getURL()
document.getElementById('testURL').addEventListener('click', () => {
  const resultDiv = document.getElementById('basicResults');
  resultDiv.style.display = 'block';
  
  console.log('✅ [Popup] Testing getURL()');
  
  try {
    const iconURL = chrome.runtime.getURL('icon48.png');
    const popupURL = chrome.runtime.getURL('popup.html');
    
    if (iconURL && popupURL) {
      resultDiv.className = 'result success';
      resultDiv.textContent = `✅ SUCCESS\nicon48.png: ${iconURL}\npopup.html: ${popupURL}`;
      console.log('   ✅ PASS: getURL() works in popup');
      console.log('   Icon URL:', iconURL);
      console.log('   Popup URL:', popupURL);
    } else {
      resultDiv.className = 'result error';
      resultDiv.textContent = '❌ FAIL\ngetURL() returned invalid URLs';
      console.error('   ❌ FAIL: Invalid URLs returned');
    }
  } catch (error) {
    resultDiv.className = 'result error';
    resultDiv.textContent = `❌ ERROR\n${error.message}`;
    console.error('   ❌ FAIL: getURL() threw error:', error);
  }
});

// Test sendMessage()
document.getElementById('testSendMessage').addEventListener('click', () => {
  const resultDiv = document.getElementById('messageResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Sending message to background...';
  
  console.log('✅ [Popup] Testing sendMessage() to background');
  
  chrome.runtime.sendMessage(
    { type: 'PING', from: 'popup', timestamp: Date.now() },
    (response) => {
      if (chrome.runtime.lastError) {
        resultDiv.className = 'result error';
        resultDiv.textContent = `❌ ERROR\n${chrome.runtime.lastError.message}`;
        console.error('   ❌ FAIL: sendMessage error:', chrome.runtime.lastError);
      } else if (response) {
        resultDiv.className = 'result success';
        resultDiv.textContent = `✅ SUCCESS\nReceived response:\n${JSON.stringify(response, null, 2)}`;
        console.log('   ✅ PASS: sendMessage() works from popup');
        console.log('   Response:', response);
      } else {
        resultDiv.className = 'result error';
        resultDiv.textContent = '❌ FAIL\nNo response received';
        console.error('   ❌ FAIL: No response from background');
      }
    }
  );
});

// Test connect()
document.getElementById('testConnect').addEventListener('click', () => {
  const resultDiv = document.getElementById('messageResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Testing connect()...';
  
  console.log('✅ [Popup] Testing connect()');
  
  try {
    const port = chrome.runtime.connect({ name: 'popup-test' });
    
    port.onMessage.addListener((message) => {
      console.log('   📥 Message on port:', message);
      if (message.type === 'PORT_PONG') {
        resultDiv.className = 'result success';
        resultDiv.textContent = `✅ SUCCESS\nPort connected and messaging works!\nReceived: ${JSON.stringify(message, null, 2)}`;
        console.log('   ✅ PASS: Port connection and messaging works');
      }
    });
    
    port.onDisconnect.addListener(() => {
      console.log('   🔌 Port disconnected');
    });
    
    // Send a PING message through the port
    port.postMessage({ type: 'PORT_PING', from: 'popup', timestamp: Date.now() });
    
    setTimeout(() => {
      if (resultDiv.textContent.includes('⏳')) {
        resultDiv.className = 'result error';
        resultDiv.textContent = '⚠️ WARNING\nPort connected but no response received\nCheck if background script handles port connections';
        console.warn('   ⚠️  Port connected but no response');
      }
    }, 2000);
    
    console.log('   ✅ Port created successfully');
  } catch (error) {
    resultDiv.className = 'result error';
    resultDiv.textContent = `❌ ERROR\n${error.message}`;
    console.error('   ❌ FAIL: connect() threw error:', error);
  }
});

// View console button
document.getElementById('viewConsole').addEventListener('click', () => {
  alert('Open the browser\'s Developer Console (Cmd+Option+I) to see detailed test output from:\n\n• Background script\n• Content script\n• Popup script\n\nAll test results are logged there.');
});

console.log('🎨 [Runtime Test] Popup script ready');
