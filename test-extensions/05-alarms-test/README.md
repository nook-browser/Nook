# Alarms API Test Extension

Tests the `chrome.alarms` API implementation for Bitwarden compatibility.

## Features Tested

- ✅ `chrome.alarms.create()` - Create one-time and repeating alarms
- ✅ `chrome.alarms.get()` - Retrieve specific alarm
- ✅ `chrome.alarms.getAll()` - List all active alarms
- ✅ `chrome.alarms.clear()` - Remove specific alarm
- ✅ `chrome.alarms.clearAll()` - Remove all alarms
- ✅ `chrome.alarms.onAlarm` - Listen for alarm events

## What This Tests

### One-Time Alarms
- Short delays (5s, 30s)
- Using `delayInMinutes` parameter
- Automatic cleanup after firing

### Repeating Alarms
- Periodic execution
- Using `periodInMinutes` parameter
- Automatic rescheduling

### Alarm Management
- Listing active alarms
- Clearing specific alarms
- Clearing all alarms
- Overwriting existing alarms with same name

### Event Handling
- `onAlarm` event dispatching
- Multiple listeners
- Event payload structure

## How to Use

1. Load the extension in Nook
2. Open the popup to see the test interface
3. Click "Create 5s Alarm" to test short-delay alarm
4. Click "Create Repeating" to test periodic alarm
5. Watch console logs for alarm firing events
6. Use "List All Alarms" to see active alarms
7. Use "Clear All Alarms" to clean up

## Expected Behavior

- Alarms should fire at scheduled times
- Notifications appear when alarms fire
- Background script logs alarm events
- Repeating alarms automatically reschedule
- One-time alarms are removed after firing

## Bitwarden Use Cases

This API enables critical Bitwarden features:

- **Auto-lock timeout**: Vault locks after inactivity period
- **Background sync**: Periodic sync with server
- **Token refresh**: Keep auth tokens fresh
- **Session management**: Handle session timeouts

## Implementation Notes

- Alarms persist across browser restarts (stored in memory for now)
- Minimum delay: ~5 seconds (configurable)
- Maximum: unlimited
- Precision: ±30 seconds (typical browser behavior)

