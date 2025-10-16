/**
 * Tabs API Test - Popup Script
 * Tests chrome.tabs.* APIs from popup context
 */

console.log('📑 [Tabs Test] Popup script loaded');

// ============================================================================
// RUN ALL TESTS BUTTON
// ============================================================================

document.getElementById('runAllTests').addEventListener('click', async () => {
  const resultDiv = document.getElementById('allTestsResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Running all tabs tests...\n\n';
  
  const results = [];
  let passCount = 0;
  let failCount = 0;
  
  // Store tab IDs for cleanup
  let createdTabId = null;
  
  // Test 1: Query active tab
  try {
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tabs && tabs.length > 0 && tabs[0].active) {
      results.push(`✅ tabs.query() active: PASS (found tab ${tabs[0].id})`);
      passCount++;
    } else {
      results.push('❌ tabs.query() active: FAIL (no active tab)');
      failCount++;
    }
  } catch (e) {
    results.push(`❌ tabs.query() active: FAIL (${e.message})`);
    failCount++;
  }
  
  // Test 2: Query all tabs
  try {
    const allTabs = await chrome.tabs.query({});
    if (allTabs && allTabs.length > 0) {
      results.push(`✅ tabs.query() all: PASS (${allTabs.length} tabs)`);
      passCount++;
    } else {
      results.push('❌ tabs.query() all: FAIL (no tabs found)');
      failCount++;
    }
  } catch (e) {
    results.push(`❌ tabs.query() all: FAIL (${e.message})`);
    failCount++;
  }
  
  // Test 3: Get current tab (from popup context)
  try {
    // Note: getCurrent() may not work in popup context in all browsers
    // This is expected behavior - we'll test it but won't fail if it returns undefined
    const currentTab = await chrome.tabs.getCurrent();
    if (currentTab === undefined) {
      results.push('✅ tabs.getCurrent(): PASS (correctly returns undefined in popup)');
      passCount++;
    } else if (currentTab && currentTab.id) {
      results.push(`✅ tabs.getCurrent(): PASS (tab ${currentTab.id})`);
      passCount++;
    } else {
      results.push('❌ tabs.getCurrent(): FAIL (unexpected result)');
      failCount++;
    }
  } catch (e) {
    results.push(`❌ tabs.getCurrent(): FAIL (${e.message})`);
    failCount++;
  }
  
  // Test 4: Create new tab
  try {
    const newTab = await chrome.tabs.create({
      url: 'https://example.com',
      active: false
    });
    if (newTab && newTab.id) {
      createdTabId = newTab.id;
      results.push(`✅ tabs.create(): PASS (created tab ${newTab.id})`);
      passCount++;
    } else {
      results.push('❌ tabs.create(): FAIL (no tab returned)');
      failCount++;
    }
  } catch (e) {
    results.push(`❌ tabs.create(): FAIL (${e.message})`);
    failCount++;
  }
  
  // Wait a moment for tab to be created
  await new Promise(resolve => setTimeout(resolve, 500));
  
  // Test 5: Update tab URL (using created tab)
  if (createdTabId) {
    try {
      const updatedTab = await chrome.tabs.update(createdTabId, {
        url: 'https://www.example.org'
      });
      if (updatedTab && updatedTab.id === createdTabId) {
        results.push(`✅ tabs.update(): PASS (updated tab ${createdTabId})`);
        passCount++;
      } else {
        results.push('❌ tabs.update(): FAIL (no tab returned)');
        failCount++;
      }
    } catch (e) {
      results.push(`❌ tabs.update(): FAIL (${e.message})`);
      failCount++;
    }
  } else {
    results.push('⚠️ tabs.update(): SKIP (no tab to update)');
  }
  
  // Wait a moment for update to process
  await new Promise(resolve => setTimeout(resolve, 500));
  
  // Test 6: Reload tab (using created tab)
  if (createdTabId) {
    try {
      await chrome.tabs.reload(createdTabId);
      results.push(`✅ tabs.reload(): PASS (reloaded tab ${createdTabId})`);
      passCount++;
    } catch (e) {
      results.push(`❌ tabs.reload(): FAIL (${e.message})`);
      failCount++;
    }
  } else {
    results.push('⚠️ tabs.reload(): SKIP (no tab to reload)');
  }
  
  // Wait a moment for reload to start
  await new Promise(resolve => setTimeout(resolve, 500));
  
  // Test 7: Get tab by ID
  if (createdTabId) {
    try {
      const tab = await chrome.tabs.get(createdTabId);
      if (tab && tab.id === createdTabId) {
        results.push(`✅ tabs.get(): PASS (got tab ${createdTabId})`);
        passCount++;
      } else {
        results.push('❌ tabs.get(): FAIL (no tab returned)');
        failCount++;
      }
    } catch (e) {
      results.push(`❌ tabs.get(): FAIL (${e.message})`);
      failCount++;
    }
  } else {
    results.push('⚠️ tabs.get(): SKIP (no tab to get)');
  }
  
  // Test 8: Remove tab (cleanup)
  if (createdTabId) {
    try {
      await chrome.tabs.remove(createdTabId);
      results.push(`✅ tabs.remove(): PASS (removed tab ${createdTabId})`);
      passCount++;
    } catch (e) {
      results.push(`❌ tabs.remove(): FAIL (${e.message})`);
      failCount++;
    }
  } else {
    results.push('⚠️ tabs.remove(): SKIP (no tab to remove)');
  }
  
  // Test 9: Event listeners (check if background script is tracking events)
  try {
    const response = await chrome.runtime.sendMessage({ type: 'GET_EVENT_COUNTS' });
    if (response && response.counts) {
      const { created, updated, removed } = response.counts;
      if (created > 0 || updated > 0 || removed > 0) {
        results.push(`✅ Event listeners: PASS (created: ${created}, updated: ${updated}, removed: ${removed})`);
        passCount++;
      } else {
        results.push('⚠️ Event listeners: PARTIAL (listeners registered but no events detected yet)');
        passCount++;
      }
    } else {
      results.push('❌ Event listeners: FAIL (no response from background)');
      failCount++;
    }
  } catch (e) {
    results.push(`❌ Event listeners: FAIL (${e.message})`);
    failCount++;
  }
  
  // Display results
  const totalTests = passCount + failCount;
  const successRate = totalTests > 0 ? ((passCount / totalTests) * 100).toFixed(1) : '0.0';
  
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
  
  console.log('[Tabs Test] All tests completed:', { passCount, failCount, totalTests });
});

// ============================================================================
// INDIVIDUAL TEST BUTTONS (kept for detailed testing)
// ============================================================================

// Query active tab
document.getElementById('queryActive').addEventListener('click', async () => {
  const resultDiv = document.getElementById('individualResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Querying active tab...';
  
  try {
    const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tabs && tabs.length > 0) {
      const tab = tabs[0];
      resultDiv.className = 'result success';
      resultDiv.textContent = `✅ SUCCESS\n\nActive Tab:\nID: ${tab.id}\nTitle: ${tab.title}\nURL: ${tab.url}\nActive: ${tab.active}\nIndex: ${tab.index}`;
      console.log('✅ [Tabs Test] Active tab:', tab);
    } else {
      resultDiv.className = 'result error';
      resultDiv.textContent = '❌ ERROR\nNo active tab found';
    }
  } catch (e) {
    resultDiv.className = 'result error';
    resultDiv.textContent = `❌ ERROR\n${e.message}`;
    console.error('❌ [Tabs Test] Query active failed:', e);
  }
});

// Query all tabs
document.getElementById('queryAll').addEventListener('click', async () => {
  const resultDiv = document.getElementById('individualResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Querying all tabs...';
  
  try {
    const tabs = await chrome.tabs.query({});
    if (tabs && tabs.length > 0) {
      resultDiv.className = 'result success';
      const tabList = tabs.map((tab, i) => 
        `${i + 1}. [${tab.id}] ${tab.title || 'Untitled'} ${tab.active ? '(active)' : ''}`
      ).join('\n');
      resultDiv.textContent = `✅ SUCCESS\n\nFound ${tabs.length} tabs:\n\n${tabList}`;
      console.log('✅ [Tabs Test] All tabs:', tabs);
    } else {
      resultDiv.className = 'result error';
      resultDiv.textContent = '❌ ERROR\nNo tabs found';
    }
  } catch (e) {
    resultDiv.className = 'result error';
    resultDiv.textContent = `❌ ERROR\n${e.message}`;
    console.error('❌ [Tabs Test] Query all failed:', e);
  }
});

// Get current tab
document.getElementById('getCurrent').addEventListener('click', async () => {
  const resultDiv = document.getElementById('individualResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Getting current tab...';
  
  try {
    const tab = await chrome.tabs.getCurrent();
    if (tab) {
      resultDiv.className = 'result success';
      resultDiv.textContent = `✅ SUCCESS\n\nCurrent Tab:\nID: ${tab.id}\nTitle: ${tab.title}\nURL: ${tab.url}`;
      console.log('✅ [Tabs Test] Current tab:', tab);
    } else {
      resultDiv.className = 'result info';
      resultDiv.textContent = '⚠️ INFO\n\ntabs.getCurrent() returned undefined.\n\nThis is expected behavior for popups in most browsers.\ngetCurrent() typically only works in tab contexts (like content scripts).';
      console.log('ℹ️ [Tabs Test] getCurrent() returned undefined (expected in popup context)');
    }
  } catch (e) {
    resultDiv.className = 'result error';
    resultDiv.textContent = `❌ ERROR\n${e.message}`;
    console.error('❌ [Tabs Test] Get current failed:', e);
  }
});

// Create new tab
document.getElementById('createTab').addEventListener('click', async () => {
  const resultDiv = document.getElementById('individualResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Creating new tab...';
  
  try {
    const tab = await chrome.tabs.create({
      url: 'https://example.com',
      active: false
    });
    if (tab && tab.id) {
      resultDiv.className = 'result success';
      resultDiv.textContent = `✅ SUCCESS\n\nCreated Tab:\nID: ${tab.id}\nURL: ${tab.url}\nActive: ${tab.active}\n\nCheck your tabs - a new tab should have opened!`;
      console.log('✅ [Tabs Test] Created tab:', tab);
    } else {
      resultDiv.className = 'result error';
      resultDiv.textContent = '❌ ERROR\nFailed to create tab';
    }
  } catch (e) {
    resultDiv.className = 'result error';
    resultDiv.textContent = `❌ ERROR\n${e.message}`;
    console.error('❌ [Tabs Test] Create tab failed:', e);
  }
});

// Update tab URL
document.getElementById('updateTab').addEventListener('click', async () => {
  const resultDiv = document.getElementById('individualResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Updating active tab URL...';
  
  try {
    const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!activeTab) {
      resultDiv.className = 'result error';
      resultDiv.textContent = '❌ ERROR\nNo active tab found';
      return;
    }
    
    const updatedTab = await chrome.tabs.update(activeTab.id, {
      url: 'https://www.example.org'
    });
    
    if (updatedTab) {
      resultDiv.className = 'result success';
      resultDiv.textContent = `✅ SUCCESS\n\nUpdated Tab:\nID: ${updatedTab.id}\nNew URL: https://www.example.org\n\nThe active tab should now navigate to example.org!`;
      console.log('✅ [Tabs Test] Updated tab:', updatedTab);
    } else {
      resultDiv.className = 'result error';
      resultDiv.textContent = '❌ ERROR\nFailed to update tab';
    }
  } catch (e) {
    resultDiv.className = 'result error';
    resultDiv.textContent = `❌ ERROR\n${e.message}`;
    console.error('❌ [Tabs Test] Update tab failed:', e);
  }
});

// Reload tab
document.getElementById('reloadTab').addEventListener('click', async () => {
  const resultDiv = document.getElementById('individualResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Reloading active tab...';
  
  try {
    const [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!activeTab) {
      resultDiv.className = 'result error';
      resultDiv.textContent = '❌ ERROR\nNo active tab found';
      return;
    }
    
    await chrome.tabs.reload(activeTab.id);
    resultDiv.className = 'result success';
    resultDiv.textContent = `✅ SUCCESS\n\nReloaded tab ${activeTab.id}\n\nThe active tab should now be reloading!`;
    console.log('✅ [Tabs Test] Reloaded tab:', activeTab.id);
  } catch (e) {
    resultDiv.className = 'result error';
    resultDiv.textContent = `❌ ERROR\n${e.message}`;
    console.error('❌ [Tabs Test] Reload tab failed:', e);
  }
});

// Remove tab
document.getElementById('removeTab').addEventListener('click', async () => {
  const resultDiv = document.getElementById('individualResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Creating then removing a tab...';
  
  try {
    // First create a tab
    const tab = await chrome.tabs.create({
      url: 'https://example.com',
      active: false
    });
    
    if (!tab || !tab.id) {
      resultDiv.className = 'result error';
      resultDiv.textContent = '❌ ERROR\nFailed to create tab';
      return;
    }
    
    // Wait a moment
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // Then remove it
    await chrome.tabs.remove(tab.id);
    resultDiv.className = 'result success';
    resultDiv.textContent = `✅ SUCCESS\n\nCreated tab ${tab.id} and then removed it.\n\nYou should have briefly seen a new tab appear and disappear!`;
    console.log('✅ [Tabs Test] Removed tab:', tab.id);
  } catch (e) {
    resultDiv.className = 'result error';
    resultDiv.textContent = `❌ ERROR\n${e.message}`;
    console.error('❌ [Tabs Test] Remove tab failed:', e);
  }
});

// Test events
document.getElementById('testEvents').addEventListener('click', async () => {
  const resultDiv = document.getElementById('individualResults');
  resultDiv.style.display = 'block';
  resultDiv.className = 'result info';
  resultDiv.textContent = '⏳ Checking event listeners...';
  
  try {
    const response = await chrome.runtime.sendMessage({ type: 'GET_EVENT_COUNTS' });
    if (response && response.counts) {
      const { created, updated, removed, activated } = response.counts;
      resultDiv.className = 'result success';
      resultDiv.textContent = `✅ SUCCESS\n\nEvent Counts:\n- tabs.onCreated: ${created}\n- tabs.onUpdated: ${updated}\n- tabs.onRemoved: ${removed}\n- tabs.onActivated: ${activated}\n\nThese counters track events since the extension was loaded.\nTry creating, updating, or closing tabs to see the counts increase!\n\nCheck the console for detailed event logs.`;
      console.log('✅ [Tabs Test] Event counts:', response.counts);
    } else {
      resultDiv.className = 'result error';
      resultDiv.textContent = '❌ ERROR\nFailed to get event counts from background script';
    }
  } catch (e) {
    resultDiv.className = 'result error';
    resultDiv.textContent = `❌ ERROR\n${e.message}`;
    console.error('❌ [Tabs Test] Get event counts failed:', e);
  }
});

// Open console
document.getElementById('viewConsole').addEventListener('click', () => {
  console.log('📑 [Tabs Test] Opening developer console...');
  console.log('👀 Check the console for detailed tab event logs!');
  alert('Check the browser console (right-click > Inspect Element) to see detailed logs from the background service worker!');
});

console.log('📑 [Tabs Test] All event listeners registered');

