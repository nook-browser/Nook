/**
 * Tabs API Test - Background Service Worker
 * Tests chrome.tabs.* event listeners and background context APIs
 */

console.log('📑 [Tabs Test] Background service worker started');

// Track event counts for testing
const eventCounts = {
  created: 0,
  updated: 0,
  removed: 0,
  activated: 0
};

// Listen for tab creation
chrome.tabs.onCreated.addListener((tab) => {
  eventCounts.created++;
  console.log('📑 [Background] Tab created:', {
    id: tab.id,
    url: tab.url,
    title: tab.title,
    active: tab.active,
    totalCreated: eventCounts.created
  });
});

// Listen for tab updates (URL changes, loading state, etc.)
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  eventCounts.updated++;
  console.log('📑 [Background] Tab updated:', {
    id: tabId,
    changeInfo,
    url: tab.url,
    status: tab.status,
    totalUpdated: eventCounts.updated
  });
});

// Listen for tab removal
chrome.tabs.onRemoved.addListener((tabId, removeInfo) => {
  eventCounts.removed++;
  console.log('📑 [Background] Tab removed:', {
    id: tabId,
    windowId: removeInfo.windowId,
    isWindowClosing: removeInfo.isWindowClosing,
    totalRemoved: eventCounts.removed
  });
});

// Listen for tab activation (switching tabs)
chrome.tabs.onActivated.addListener((activeInfo) => {
  eventCounts.activated++;
  console.log('📑 [Background] Tab activated:', {
    tabId: activeInfo.tabId,
    windowId: activeInfo.windowId,
    totalActivated: eventCounts.activated
  });
});

// Handle messages from popup
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  console.log('📑 [Background] Received message:', message);
  
  if (message.type === 'GET_EVENT_COUNTS') {
    sendResponse({ counts: eventCounts });
    return true;
  }
  
  if (message.type === 'RESET_EVENT_COUNTS') {
    eventCounts.created = 0;
    eventCounts.updated = 0;
    eventCounts.removed = 0;
    eventCounts.activated = 0;
    sendResponse({ success: true });
    return true;
  }
});

console.log('📑 [Background] All event listeners registered');
console.log('   ✅ tabs.onCreated');
console.log('   ✅ tabs.onUpdated');
console.log('   ✅ tabs.onRemoved');
console.log('   ✅ tabs.onActivated');

