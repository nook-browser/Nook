# Storage API Test Extension

## Purpose
Tests the implementation of `chrome.storage.*` APIs in Nook browser.

## APIs Tested

### chrome.storage.local:
- ✅ `set()` - Write data to local storage
- ✅ `get()` - Read specific keys
- ✅ `get(null)` - Read all data
- ✅ `getBytesInUse()` - Check storage size
- ✅ `remove()` - Remove specific keys
- ✅ `clear()` - Clear all data
- ✅ Data type support: strings, numbers, booleans, arrays, objects, nested objects
- ✅ Large data storage (~100KB+)

### chrome.storage.session:
- ✅ `set()` - Write data to session storage
- ✅ `get()` - Read session data
- ✅ `getBytesInUse()` - Check session storage size
- ✅ Session persistence (until browser restart)

### chrome.storage.onChanged:
- ✅ Event listener registration
- ✅ Change detection across storage areas
- ✅ Old value / new value tracking

## Installation

1. Open Nook browser
2. Navigate to extension settings
3. Click "Load Unpacked" or "Install from folder"
4. Select the `test-extensions/02-storage-test` directory

## Usage

### Automatic Tests (Background Script)
The background script runs a comprehensive test suite automatically on load:
- All storage.local operations
- All storage.session operations
- onChanged event handling
- Large data stress test
- Success rate calculation

Check the console for results.

### Interactive Tests (Popup)
Click the extension icon to open the popup and:
- **Local Storage**: Write, read, and clear local data
- **Session Storage**: Write and read session data
- **Advanced Tests**: Test large data and performance
- **Statistics**: View real-time storage statistics

### Expected Results
- All automatic tests should PASS
- Storage statistics should update in real-time
- Data should persist across popup opens/closes
- Session data should be lost on browser restart

## Test Coverage

This extension validates:
- **Data Integrity**: All JavaScript types stored correctly
- **Persistence**: Local data survives restarts, session doesn't
- **Size Limits**: Can handle large data (tested up to 100KB)
- **Performance**: Speed tests for write operations
- **Events**: onChanged fires correctly for all operations
- **Isolation**: Extension storage isolated from web pages

## Common Issues

- **"getBytesInUse returns 0"**: API may not be implemented yet
- **"Session storage lost on popup close"**: Check if session truly persists
- **"Large data fails"**: May hit storage quota limits
- **"onChanged not firing"**: Event system issues

## Performance Benchmarks

Expected performance on a modern Mac:
- Single write: < 5ms
- Single read: < 2ms
- 100 sequential writes: < 500ms
- Large data (100KB): < 50ms

