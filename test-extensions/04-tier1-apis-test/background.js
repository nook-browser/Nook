// Tier 1 APIs Test Extension - Background Script
// Tests: chrome.action, chrome.contextMenus, chrome.notifications, chrome.commands

console.log('🚀 Tier 1 APIs Test Extension - Background script loaded');

// ============================================================================
// 1. CHROME.ACTION API TESTS
// ============================================================================

// Test action.onClicked
chrome.action.onClicked.addListener((tab) => {
  console.log('✅ [chrome.action] Action clicked!', tab);
  
  // Show notification when action is clicked
  chrome.notifications.create('action-clicked', {
    type: 'basic',
    iconUrl: 'icon128.png',
    title: 'Action Clicked!',
    message: `Toolbar icon was clicked on tab: ${tab.title}`,
    priority: 1
  });
});

// Test badge text
chrome.action.setBadgeText({ text: '4' });
console.log('✅ [chrome.action] Badge text set to "4"');

// Test badge background color
chrome.action.setBadgeBackgroundColor({ color: '#FF0000' });
console.log('✅ [chrome.action] Badge color set to red');

// Test title
chrome.action.setTitle({ title: 'Tier 1 APIs Test - Ready!' });
console.log('✅ [chrome.action] Title updated');

// ============================================================================
// 2. CHROME.CONTEXTMENUS API TESTS
// ============================================================================

// Create parent menu item
chrome.contextMenus.create({
  id: 'tier1-parent',
  title: 'Tier 1 API Tests',
  contexts: ['all']
}, () => {
  console.log('✅ [chrome.contextMenus] Parent menu created');
});

// Create submenu items
chrome.contextMenus.create({
  id: 'test-notification',
  parentId: 'tier1-parent',
  title: 'Show Test Notification',
  contexts: ['all']
}, () => {
  console.log('✅ [chrome.contextMenus] Notification submenu created');
});

chrome.contextMenus.create({
  id: 'test-command',
  parentId: 'tier1-parent',
  title: 'Trigger Test Command',
  contexts: ['all']
}, () => {
  console.log('✅ [chrome.contextMenus] Command submenu created');
});

chrome.contextMenus.create({
  id: 'separator-1',
  parentId: 'tier1-parent',
  type: 'separator',
  contexts: ['all']
});

chrome.contextMenus.create({
  id: 'page-info',
  parentId: 'tier1-parent',
  title: 'Page Info: %s',
  contexts: ['selection']
}, () => {
  console.log('✅ [chrome.contextMenus] Selection menu created');
});

// Handle context menu clicks
chrome.contextMenus.onClicked.addListener((info, tab) => {
  console.log('✅ [chrome.contextMenus] Menu clicked:', info.menuItemId);
  
  switch (info.menuItemId) {
    case 'test-notification':
      chrome.notifications.create('context-menu-test', {
        type: 'basic',
        iconUrl: 'icon128.png',
        title: 'Context Menu Test',
        message: 'You clicked "Show Test Notification" from the context menu!',
        priority: 2
      });
      break;
      
    case 'test-command':
      console.log('🎹 [chrome.commands] Simulating command trigger...');
      chrome.notifications.create('command-test', {
        type: 'basic',
        iconUrl: 'icon128.png',
        title: 'Command Test',
        message: 'Try pressing Ctrl+Shift+Y to trigger the test command!',
        priority: 1
      });
      break;
      
    case 'page-info':
      chrome.notifications.create('page-info', {
        type: 'basic',
        iconUrl: 'icon128.png',
        title: 'Selected Text',
        message: `You selected: "${info.selectionText}"`,
        priority: 1
      });
      break;
  }
});

// ============================================================================
// 3. CHROME.NOTIFICATIONS API TESTS
// ============================================================================

// Test creating a notification with buttons
function createAdvancedNotification() {
  chrome.notifications.create('advanced-test', {
    type: 'basic',
    iconUrl: 'icon128.png',
    title: 'Advanced Notification Test',
    message: 'This notification tests all features!',
    contextMessage: 'Context: Tier 1 APIs Test',
    priority: 2,
    buttons: [
      { title: 'Button 1' },
      { title: 'Button 2' }
    ]
  }, (notificationId) => {
    console.log('✅ [chrome.notifications] Advanced notification created:', notificationId);
  });
}

// Handle notification clicks
chrome.notifications.onClicked.addListener((notificationId) => {
  console.log('✅ [chrome.notifications] Notification clicked:', notificationId);
  
  // Clear the notification
  chrome.notifications.clear(notificationId, (wasCleared) => {
    console.log('✅ [chrome.notifications] Notification cleared:', wasCleared);
  });
});

// Handle notification button clicks
chrome.notifications.onButtonClicked.addListener((notificationId, buttonIndex) => {
  console.log('✅ [chrome.notifications] Button clicked:', notificationId, 'button', buttonIndex);
  
  chrome.notifications.create(`button-${buttonIndex}-response`, {
    type: 'basic',
    iconUrl: 'icon128.png',
    title: 'Button Clicked!',
    message: `You clicked button ${buttonIndex + 1}`,
    priority: 1
  });
});

// Handle notification closed
chrome.notifications.onClosed.addListener((notificationId, byUser) => {
  console.log('✅ [chrome.notifications] Notification closed:', notificationId, 'by user:', byUser);
});

// ============================================================================
// 4. CHROME.COMMANDS API TESTS
// ============================================================================

// Handle keyboard commands
chrome.commands.onCommand.addListener((command) => {
  console.log('✅ [chrome.commands] Command triggered:', command);
  
  switch (command) {
    case 'test-command':
      chrome.notifications.create('command-triggered', {
        type: 'basic',
        iconUrl: 'icon128.png',
        title: 'Keyboard Shortcut Works!',
        message: 'You pressed Ctrl+Shift+Y to trigger the test command!',
        priority: 2
      });
      
      // Update badge to show command was triggered
      chrome.action.setBadgeText({ text: '✓' });
      chrome.action.setBadgeBackgroundColor({ color: '#00FF00' });
      
      setTimeout(() => {
        chrome.action.setBadgeText({ text: '4' });
        chrome.action.setBadgeBackgroundColor({ color: '#FF0000' });
      }, 2000);
      break;
      
    case 'show-notification':
      createAdvancedNotification();
      break;
  }
});

// Get all registered commands
chrome.commands.getAll((commands) => {
  console.log('✅ [chrome.commands] Registered commands:', commands);
  
  commands.forEach(command => {
    console.log(`  - ${command.name}: ${command.shortcut || 'no shortcut'} - ${command.description || 'no description'}`);
  });
});

// ============================================================================
// INITIALIZATION
// ============================================================================

console.log('🎉 All Tier 1 API tests initialized!');
console.log('📋 Available features:');
console.log('  1. Click the toolbar icon (or press Ctrl+Shift+U)');
console.log('  2. Right-click anywhere to see context menus');
console.log('  3. Press Ctrl+Shift+Y for test command');
console.log('  4. Press Ctrl+Shift+N for advanced notification');
console.log('  5. Open the popup for interactive tests');

// Show welcome notification after a short delay
setTimeout(() => {
  chrome.notifications.create('welcome', {
    type: 'basic',
    iconUrl: 'icon128.png',
    title: 'Tier 1 APIs Test Ready!',
    message: 'All APIs loaded. Try the keyboard shortcuts or right-click menu!',
    priority: 1
  });
}, 1000);

