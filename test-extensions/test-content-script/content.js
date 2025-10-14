console.log('🎯 [Content Script] Injected into page:', window.location.href);

// Add a visible indicator to the page
const indicator = document.createElement('div');
indicator.style.cssText = `
    position: fixed;
    top: 10px;
    right: 10px;
    background: #4CAF50;
    color: white;
    padding: 10px 15px;
    border-radius: 4px;
    z-index: 999999;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    font-size: 14px;
    box-shadow: 0 2px 5px rgba(0,0,0,0.2);
`;
indicator.textContent = '✅ Content Script Loaded';
document.body.appendChild(indicator);

// Remove indicator after 3 seconds
setTimeout(() => {
    indicator.style.transition = 'opacity 0.5s';
    indicator.style.opacity = '0';
    setTimeout(() => indicator.remove(), 500);
}, 3000);

// Listen for messages from popup
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    console.log('📨 [Content Script] Received message:', message);
    
    if (message.action === 'ping') {
        sendResponse({
            success: true,
            url: window.location.href,
            title: document.title,
            timestamp: Date.now()
        });
    }
    
    return true;
});

console.log('✅ [Content Script] Ready and listening');

