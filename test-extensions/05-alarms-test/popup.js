console.log('🔔 [Alarms Test Popup] Popup script loaded');

const statusEl = document.getElementById('status');
const alarmsListEl = document.getElementById('alarmsList');

function showStatus(message, isError = false) {
  statusEl.textContent = message;
  statusEl.className = 'status' + (isError ? ' error' : '');
  console.log(isError ? '❌' : '✅', message);
}

function formatTime(timestamp) {
  const date = new Date(timestamp);
  const now = new Date();
  const diff = (date - now) / 1000; // seconds
  
  if (diff < 0) {
    return `${Math.abs(Math.floor(diff))}s ago`;
  } else if (diff < 60) {
    return `in ${Math.floor(diff)}s`;
  } else if (diff < 3600) {
    return `in ${Math.floor(diff / 60)}m`;
  } else {
    return date.toLocaleTimeString();
  }
}

function displayAlarms(alarms) {
  if (!alarms || alarms.length === 0) {
    alarmsListEl.innerHTML = '<div style="color: #999; text-align: center; padding: 20px;">No active alarms</div>';
    return;
  }
  
  alarmsListEl.innerHTML = alarms.map(alarm => `
    <div class="alarm-item">
      <div class="alarm-name">${alarm.name || '(unnamed)'}</div>
      <div class="alarm-time">
        Scheduled: ${formatTime(alarm.scheduledTime)}
        ${alarm.periodInMinutes ? ` | Repeats every ${alarm.periodInMinutes} min` : ' | One-time'}
      </div>
    </div>
  `).join('');
}

// Create 5 second alarm
document.getElementById('create5s').addEventListener('click', () => {
  console.log('🔔 Creating 5s alarm');
  chrome.alarms.create('test-5s', {
    delayInMinutes: 5 / 60  // 5 seconds
  }, () => {
    if (chrome.runtime.lastError) {
      showStatus(`Error: ${chrome.runtime.lastError.message}`, true);
    } else {
      showStatus('✅ Created 5-second alarm');
      setTimeout(() => listAlarms(), 100);
    }
  });
});

// Create 30 second alarm
document.getElementById('create30s').addEventListener('click', () => {
  console.log('🔔 Creating 30s alarm');
  chrome.alarms.create('test-30s', {
    delayInMinutes: 0.5  // 30 seconds
  }, () => {
    if (chrome.runtime.lastError) {
      showStatus(`Error: ${chrome.runtime.lastError.message}`, true);
    } else {
      showStatus('✅ Created 30-second alarm');
      setTimeout(() => listAlarms(), 100);
    }
  });
});

// Create repeating alarm
document.getElementById('createRepeating').addEventListener('click', () => {
  console.log('🔔 Creating repeating alarm');
  chrome.alarms.create('test-repeating', {
    delayInMinutes: 1,
    periodInMinutes: 1
  }, () => {
    if (chrome.runtime.lastError) {
      showStatus(`Error: ${chrome.runtime.lastError.message}`, true);
    } else {
      showStatus('✅ Created repeating alarm (1 min)');
      setTimeout(() => listAlarms(), 100);
    }
  });
});

// List all alarms
function listAlarms() {
  console.log('🔔 Listing all alarms');
  chrome.alarms.getAll((alarms) => {
    if (chrome.runtime.lastError) {
      showStatus(`Error: ${chrome.runtime.lastError.message}`, true);
      return;
    }
    console.log('🔔 Got alarms:', alarms);
    displayAlarms(alarms);
    showStatus(`Found ${alarms.length} active alarm(s)`);
  });
}

document.getElementById('listAlarms').addEventListener('click', listAlarms);

// Clear all alarms
document.getElementById('clearAll').addEventListener('click', () => {
  console.log('🔔 Clearing all alarms');
  chrome.alarms.clearAll((wasCleared) => {
    if (chrome.runtime.lastError) {
      showStatus(`Error: ${chrome.runtime.lastError.message}`, true);
    } else {
      showStatus(wasCleared ? '✅ All alarms cleared' : 'No alarms to clear');
      setTimeout(() => listAlarms(), 100);
    }
  });
});

// Listen for alarm events
chrome.alarms.onAlarm.addListener((alarm) => {
  console.log('🔔 Alarm fired in popup!', alarm);
  showStatus(`🔥 Alarm "${alarm.name}" just fired!`);
  setTimeout(() => listAlarms(), 100);
});

// Auto-refresh alarm list every 5 seconds
setInterval(listAlarms, 5000);

// Initial load
listAlarms();

console.log('✅ [Alarms Test Popup] Popup initialized');

