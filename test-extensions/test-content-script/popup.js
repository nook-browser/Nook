console.log('🎯 [Content Script Test Popup] Script loaded');

const output = document.getElementById('output');

function show(message) {
    output.textContent = message;
    console.log('📝', message);
}

document.getElementById('pingContent').addEventListener('click', async () => {
    show('Pinging content script...');
    
    try {
        // Get current tab
        const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
        
        if (!tab) {
            show('❌ No active tab found');
            return;
        }
        
        // Send message to content script in current tab
        const response = await chrome.tabs.sendMessage(tab.id, { action: 'ping' });
        
        console.log('📬 [Popup] Response from content script:', response);
        show(`✅ Content script responded!\n\nURL: ${response.url}\nTitle: ${response.title}\nTimestamp: ${new Date(response.timestamp).toISOString()}`);
        
    } catch (error) {
        console.error('❌ [Popup] Error:', error);
        show(`❌ Error: ${error.message}\n\nMake sure the content script is injected on this page.`);
    }
});

console.log('✅ [Content Script Test Popup] Ready');

