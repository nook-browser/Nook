console.log('🎯 [Background] Script loaded and running');

// Listen for messages from popup
chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    console.log('📨 [Background] Received message:', message);
    console.log('📨 [Background] Sender:', sender);
    
    // Send a response back to the popup
    sendResponse({
        success: true,
        echo: message,
        timestamp: Date.now(),
        message: 'Background received your message!'
    });
    
    return true; // Keep the message channel open for async response
});

console.log('✅ [Background] Message listener registered');

