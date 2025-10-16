console.log('🔔 [Alarms Test] Background script loaded');

// Test alarm listener
chrome.alarms.onAlarm.addListener((alarm) => {
  console.log('🔔 [Alarms Test] Alarm fired!', alarm);
  
  // Show notification when alarm fires
  chrome.notifications.create({
    type: 'basic',
    iconUrl: 'icon48.png',
    title: 'Alarm Fired!',
    message: `Alarm "${alarm.name}" triggered at ${new Date(alarm.scheduledTime).toLocaleTimeString()}`
  });
});

// Create test alarms on install
chrome.runtime.onInstalled?.addListener?.(() => {
  console.log('🔔 [Alarms Test] Extension installed, creating test alarms');
  
  // Create a one-time alarm (30 seconds)
  chrome.alarms.create('test-once', {
    delayInMinutes: 0.5  // 30 seconds
  }, () => {
    console.log('✅ [Alarms Test] One-time alarm created');
  });
  
  // Create a repeating alarm (every 1 minute)
  chrome.alarms.create('test-repeat', {
    delayInMinutes: 1,
    periodInMinutes: 1
  }, () => {
    console.log('✅ [Alarms Test] Repeating alarm created');
  });
});

// Log all active alarms
setInterval(() => {
  chrome.alarms.getAll((alarms) => {
    console.log('🔔 [Alarms Test] Active alarms:', alarms.length);
    alarms.forEach(alarm => {
      console.log(`  - ${alarm.name}: next at ${new Date(alarm.scheduledTime).toLocaleString()}`);
    });
  });
}, 10000);  // Every 10 seconds

console.log('✅ [Alarms Test] Background script initialized');

