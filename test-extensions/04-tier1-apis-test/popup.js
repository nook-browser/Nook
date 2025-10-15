// Tier 1 APIs Test Extension - Popup Script
console.log('🎨 Popup loaded');

const status = document.getElementById('status');

function setStatus(message, duration = 3000) {
  status.textContent = message;
  if (duration > 0) {
    setTimeout(() => {
      status.textContent = 'Ready! Click any button to test.';
    }, duration);
  }
}

// ============================================================================
// chrome.action tests
// ============================================================================

let badgeCounter = 0;
document.getElementById('updateBadge').addEventListener('click', () => {
  badgeCounter++;
  chrome.action.setBadgeText({ text: badgeCounter.toString() });
  chrome.action.setBadgeBackgroundColor({ 
    color: ['#FF0000', '#00FF00', '#0000FF', '#FFA500'][badgeCounter % 4]
  });
  setStatus(`✅ Badge updated to ${badgeCounter}`);
  console.log('✅ [chrome.action] Badge updated:', badgeCounter);
});

let titleCounter = 0;
const titles = [
  'Tier 1 APIs Test',
  'Testing chrome.action',
  'Badge & Title Test',
  'All Systems Go! 🚀'
];
document.getElementById('changeTitle').addEventListener('click', () => {
  titleCounter = (titleCounter + 1) % titles.length;
  chrome.action.setTitle({ title: titles[titleCounter] });
  setStatus(`✅ Title: "${titles[titleCounter]}"`);
  console.log('✅ [chrome.action] Title changed:', titles[titleCounter]);
});

document.getElementById('changeIcon').addEventListener('click', () => {
  // This would require different icon files, so we'll just show a status
  setStatus('✅ Icon color change requested');
  console.log('✅ [chrome.action] Icon color change (requires icon files)');
});

// ============================================================================
// chrome.contextMenus tests
// ============================================================================

let menuUpdateCounter = 0;
document.getElementById('updateMenu').addEventListener('click', () => {
  menuUpdateCounter++;
  
  chrome.contextMenus.update('tier1-parent', {
    title: `Tier 1 API Tests (Updated ${menuUpdateCounter}x)`
  }, () => {
    if (chrome.runtime.lastError) {
      console.error('❌ [chrome.contextMenus] Update error:', chrome.runtime.lastError);
      setStatus('❌ Menu update failed');
    } else {
      setStatus(`✅ Menu updated ${menuUpdateCounter} times`);
      console.log('✅ [chrome.contextMenus] Menu updated:', menuUpdateCounter);
    }
  });
});

// ============================================================================
// chrome.notifications tests
// ============================================================================

let notificationCounter = 0;

document.getElementById('basicNotif').addEventListener('click', () => {
  notificationCounter++;
  
  chrome.notifications.create(`basic-${notificationCounter}`, {
    type: 'basic',
    iconUrl: 'icon128.png',
    title: `Test Notification #${notificationCounter}`,
    message: 'This is a basic test notification from the popup!',
    priority: 1
  }, (notificationId) => {
    setStatus(`✅ Notification #${notificationCounter} shown`);
    console.log('✅ [chrome.notifications] Basic notification created:', notificationId);
  });
});

document.getElementById('buttonNotif').addEventListener('click', () => {
  notificationCounter++;
  
  chrome.notifications.create(`buttons-${notificationCounter}`, {
    type: 'basic',
    iconUrl: 'icon128.png',
    title: 'Interactive Notification',
    message: 'Click the buttons below to test!',
    contextMessage: `Test #${notificationCounter}`,
    priority: 2,
    buttons: [
      { title: 'Option A' },
      { title: 'Option B' }
    ]
  }, (notificationId) => {
    setStatus(`✅ Button notification #${notificationCounter} shown`);
    console.log('✅ [chrome.notifications] Button notification created:', notificationId);
  });
});

document.getElementById('clearNotif').addEventListener('click', () => {
  chrome.notifications.getAll((notifications) => {
    const notificationIds = Object.keys(notifications);
    
    if (notificationIds.length === 0) {
      setStatus('ℹ️ No notifications to clear');
      return;
    }
    
    let cleared = 0;
    notificationIds.forEach(id => {
      chrome.notifications.clear(id, (wasCleared) => {
        if (wasCleared) cleared++;
        
        if (id === notificationIds[notificationIds.length - 1]) {
          setStatus(`✅ Cleared ${cleared} notifications`);
          console.log('✅ [chrome.notifications] Cleared notifications:', cleared);
        }
      });
    });
  });
});

// ============================================================================
// chrome.commands tests
// ============================================================================

document.getElementById('listCommands').addEventListener('click', () => {
  chrome.commands.getAll((commands) => {
    const commandsList = document.getElementById('commandsList');
    
    if (commands.length === 0) {
      commandsList.innerHTML = '<div>No commands registered</div>';
      commandsList.style.display = 'block';
      setStatus('ℹ️ No commands found');
      return;
    }
    
    commandsList.innerHTML = commands.map(cmd => {
      const shortcut = cmd.shortcut ? `<span class="kbd">${cmd.shortcut}</span>` : '<em>not set</em>';
      const description = cmd.description || 'No description';
      return `
        <div>
          <strong>${cmd.name}</strong><br>
          ${shortcut} - ${description}
        </div>
      `;
    }).join('');
    
    commandsList.style.display = 'block';
    setStatus(`✅ Listed ${commands.length} commands`, 0);
    console.log('✅ [chrome.commands] Commands listed:', commands);
  });
});

// ============================================================================
// Event Listeners for Background Events
// ============================================================================

// Listen for notification events (forwarded from background)
chrome.notifications.onClicked.addListener((notificationId) => {
  console.log('🔔 [Popup] Notification clicked:', notificationId);
});

chrome.notifications.onButtonClicked.addListener((notificationId, buttonIndex) => {
  console.log('🔔 [Popup] Notification button clicked:', notificationId, buttonIndex);
});

chrome.notifications.onClosed.addListener((notificationId, byUser) => {
  console.log('🔔 [Popup] Notification closed:', notificationId, byUser);
});

// ============================================================================
// Initialize
// ============================================================================

console.log('✅ All popup event listeners initialized');

