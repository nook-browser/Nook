console.log('🎯 [Tab Events] Background script loaded');

const events = [];

function logEvent(event, details) {
    const entry = {
        event,
        details,
        timestamp: new Date().toISOString()
    };
    events.push(entry);
    console.log(`📋 [Tab Events] ${event}:`, details);
    
    // Keep only last 50 events
    if (events.length > 50) {
        events.shift();
    }
}

// Listen for tab creation
chrome.tabs.onCreated.addListener((tab) => {
    logEvent('onCreated', { id: tab.id, url: tab.url, title: tab.title });
});

// Listen for tab updates
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
    logEvent('onUpdated', { id: tabId, changeInfo, url: tab.url, title: tab.title });
});

// Listen for tab activation
chrome.tabs.onActivated.addListener((activeInfo) => {
    logEvent('onActivated', activeInfo);
});

// Listen for tab removal
chrome.tabs.onRemoved.addListener((tabId, removeInfo) => {
    logEvent('onRemoved', { id: tabId, ...removeInfo });
});

// Handle requests for event log from popup
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.action === 'getEvents') {
        sendResponse({ events });
    }
    return true;
});

console.log('✅ [Tab Events] All event listeners registered');

