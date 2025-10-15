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

// ============================================================================
// RUN ALL TESTS BUTTON
// ============================================================================

document.getElementById('runAllTests').addEventListener('click', async () => {
  const resultDiv = document.getElementById('allTestsResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Running all tests...\n\n';
  
  const results = [];
  let passCount = 0;
  let failCount = 0;
  
  // Test 1: runtime.id
  try {
    if (chrome.runtime.id) {
      results.push('✅ runtime.id: PASS');
      passCount++;
    } else {
      results.push('❌ runtime.id: FAIL (undefined)');
      failCount++;
    }
  } catch (e) {
    results.push(`❌ runtime.id: FAIL (${e.message})`);
    failCount++;
  }
  
  // Test 2: getManifest()
  try {
    const manifest = chrome.runtime.getManifest();
    if (manifest && manifest.name === 'Runtime API Test') {
      results.push('✅ getManifest(): PASS');
      passCount++;
    } else {
      results.push('❌ getManifest(): FAIL (invalid data)');
      failCount++;
    }
  } catch (e) {
    results.push(`❌ getManifest(): FAIL (${e.message})`);
    failCount++;
  }
  
  // Test 3: getURL()
  try {
    const url = chrome.runtime.getURL('popup.html');
    if (url && url.includes('popup.html')) {
      results.push('✅ getURL(): PASS');
      passCount++;
    } else {
      results.push('❌ getURL(): FAIL (invalid URL)');
      failCount++;
    }
  } catch (e) {
    results.push(`❌ getURL(): FAIL (${e.message})`);
    failCount++;
  }
  
  // Test 4: sendMessage()
  try {
    await new Promise((resolve, reject) => {
      chrome.runtime.sendMessage(
        { type: 'PING', from: 'popup-all-tests', timestamp: Date.now() },
        (response) => {
          if (chrome.runtime.lastError) {
            results.push(`❌ sendMessage(): FAIL (${chrome.runtime.lastError.message})`);
            failCount++;
            reject();
          } else if (response && response.type === 'PONG') {
            results.push('✅ sendMessage(): PASS');
            passCount++;
            resolve();
          } else {
            results.push('❌ sendMessage(): FAIL (no response)');
            failCount++;
            reject();
          }
        }
      );
      
      // Timeout after 2 seconds
      setTimeout(() => {
        reject(new Error('timeout'));
      }, 2000);
    }).catch((e) => {
      if (e && e.message === 'timeout') {
        results.push('❌ sendMessage(): FAIL (timeout)');
        failCount++;
      }
    });
  } catch (e) {
    results.push(`❌ sendMessage(): FAIL (${e.message})`);
    failCount++;
  }
  
  // Test 5: connect()
  try {
    await new Promise((resolve, reject) => {
      const port = chrome.runtime.connect({ name: 'popup-all-tests' });
      let received = false;
      
      port.onMessage.addListener((message) => {
        if (message.type === 'PORT_PONG') {
          results.push('✅ connect(): PASS');
          passCount++;
          received = true;
          port.disconnect();
          resolve();
        }
      });
      
      port.postMessage({ type: 'PORT_PING', from: 'popup-all-tests', timestamp: Date.now() });
      
      // Timeout after 2 seconds
      setTimeout(() => {
        if (!received) {
          results.push('❌ connect(): FAIL (timeout)');
          failCount++;
          port.disconnect();
          reject();
        }
      }, 2000);
    }).catch(() => {
      // Already handled
    });
  } catch (e) {
    results.push(`❌ connect(): FAIL (${e.message})`);
    failCount++;
  }
  
  // Display results
  const totalTests = passCount + failCount;
  const successRate = ((passCount / totalTests) * 100).toFixed(1);
  
  let summary = `\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`;
  summary += `RESULTS: ${passCount}/${totalTests} tests passed (${successRate}%)\n`;
  summary += `━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n`;
  
  const finalResults = summary + results.join('\n');
  
  if (failCount === 0) {
    resultDiv.className = 'result success';
    resultDiv.textContent = '🎉 ALL TESTS PASSED!\n' + finalResults;
  } else if (passCount > 0) {
    resultDiv.className = 'result info';
    resultDiv.textContent = '⚠️ SOME TESTS FAILED\n' + finalResults;
  } else {
    resultDiv.className = 'result error';
    resultDiv.textContent = '❌ ALL TESTS FAILED\n' + finalResults;
  }
  
  console.log('[Runtime Test] All tests completed:', { passCount, failCount, totalTests });
});

// ============================================================================
// INDIVIDUAL TEST BUTTONS (kept for detailed testing)
// ============================================================================

// Test runtime.id
document.getElementById('testId').addEventListener('click', () => {
  const resultDiv = document.getElementById('individualResults');
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
  const resultDiv = document.getElementById('individualResults');
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
  const resultDiv = document.getElementById('individualResults');
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
  const resultDiv = document.getElementById('individualResults');
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
  const resultDiv = document.getElementById('individualResults');
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
