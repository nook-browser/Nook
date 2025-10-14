console.log('🎯 [Storage Test] Script loaded');

const output = document.getElementById('output');

function show(message) {
    output.textContent = message;
    console.log('📝', message);
}

document.getElementById('save').addEventListener('click', async () => {
    const key = document.getElementById('key').value;
    const value = document.getElementById('value').value;
    
    if (!key) {
        show('❌ Please enter a key');
        return;
    }
    
    try {
        await chrome.storage.local.set({ [key]: value });
        show(`✅ Saved: ${key} = "${value}"`);
    } catch (error) {
        show(`❌ Error saving: ${error.message}`);
    }
});

document.getElementById('load').addEventListener('click', async () => {
    const key = document.getElementById('key').value;
    
    if (!key) {
        show('❌ Please enter a key');
        return;
    }
    
    try {
        const result = await chrome.storage.local.get(key);
        if (result[key] !== undefined) {
            show(`✅ Loaded: ${key} = "${result[key]}"`);
            document.getElementById('value').value = result[key];
        } else {
            show(`⚠️ Key not found: ${key}`);
        }
    } catch (error) {
        show(`❌ Error loading: ${error.message}`);
    }
});

document.getElementById('getAll').addEventListener('click', async () => {
    try {
        const all = await chrome.storage.local.get(null);
        show(`📦 All storage:\n${JSON.stringify(all, null, 2)}`);
    } catch (error) {
        show(`❌ Error getting all: ${error.message}`);
    }
});

document.getElementById('clear').addEventListener('click', async () => {
    try {
        await chrome.storage.local.clear();
        show('✅ Storage cleared');
    } catch (error) {
        show(`❌ Error clearing: ${error.message}`);
    }
});

console.log('✅ [Storage Test] Event listeners registered');

