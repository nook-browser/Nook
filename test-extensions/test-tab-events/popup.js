console.log('🎯 [Tab Events Popup] Script loaded');

const eventsDiv = document.getElementById('events');

async function refreshEvents() {
    try {
        const response = await chrome.runtime.sendMessage({ action: 'getEvents' });
        
        if (response.events && response.events.length > 0) {
            const formatted = response.events
                .reverse()
                .map(e => `[${e.timestamp}] ${e.event}\n${JSON.stringify(e.details, null, 2)}`)
                .join('\n\n---\n\n');
            eventsDiv.textContent = formatted;
        } else {
            eventsDiv.textContent = 'No events captured yet.\nTry creating, switching, or closing tabs!';
        }
    } catch (error) {
        eventsDiv.textContent = `❌ Error: ${error.message}`;
        console.error('Error fetching events:', error);
    }
}

document.getElementById('refresh').addEventListener('click', refreshEvents);

// Auto-refresh on load
refreshEvents();

console.log('✅ [Tab Events Popup] Ready');

