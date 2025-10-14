console.log('🎯 [Popup] Script loaded');

const responseDiv = document.getElementById('response');

function showResponse(message, isError = false) {
    responseDiv.className = isError ? 'error' : 'success';
    responseDiv.textContent = message;
    console.log(isError ? '❌' : '✅', '[Popup]', message);
}

// Test sending message to background
document.getElementById('sendMessage').addEventListener('click', async () => {
    console.log('📤 [Popup] Sending message to background...');
    showResponse('Sending message...');
    
    try {
        const response = await chrome.runtime.sendMessage({
            action: 'test',
            timestamp: Date.now(),
            message: 'Hello from popup!'
        });
        
        console.log('📬 [Popup] Received response:', response);
        showResponse(`Success! Response: ${JSON.stringify(response, null, 2)}`);
        
    } catch (error) {
        console.error('❌ [Popup] Error:', error);
        showResponse(`Error: ${error.message}`, true);
    }
});

// Test querying tabs
document.getElementById('queryTabs').addEventListener('click', async () => {
    console.log('🔍 [Popup] Querying tabs...');
    showResponse('Querying tabs...');
    
    try {
        const tabs = await chrome.tabs.query({});
        console.log('📑 [Popup] Found tabs:', tabs);
        showResponse(`Found ${tabs.length} tabs:\n${tabs.map(t => `- ${t.title}`).join('\n')}`);
        
    } catch (error) {
        console.error('❌ [Popup] Error:', error);
        showResponse(`Error: ${error.message}`, true);
    }
});

console.log('✅ [Popup] Event listeners registered');

