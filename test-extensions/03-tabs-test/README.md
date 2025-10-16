# 📑 Tabs API Test Extension

A comprehensive test extension for validating the `chrome.tabs.*` API implementation in Nook browser.

## 🎯 Purpose

This extension tests all major Tabs API functionality:
- Tab querying and retrieval
- Tab creation and manipulation
- Tab updates and navigation
- Tab reloading
- Tab removal
- Event listeners (onCreated, onUpdated, onRemoved, onActivated)

## 📋 Test Coverage

### Core APIs Tested

**Query & Retrieval:**
- ✅ `chrome.tabs.query()` - Get active tab, all tabs, filtered tabs
- ✅ `chrome.tabs.get()` - Get tab by ID
- ✅ `chrome.tabs.getCurrent()` - Get current tab (context-aware)

**Tab Manipulation:**
- ✅ `chrome.tabs.create()` - Create new tabs
- ✅ `chrome.tabs.update()` - Update tab properties (URL, etc.)
- ✅ `chrome.tabs.reload()` - Reload tabs
- ✅ `chrome.tabs.remove()` - Close tabs

**Event Listeners:**
- ✅ `chrome.tabs.onCreated` - Tab creation events
- ✅ `chrome.tabs.onUpdated` - Tab update events (URL changes, loading state)
- ✅ `chrome.tabs.onRemoved` - Tab removal events
- ✅ `chrome.tabs.onActivated` - Tab switching events

### "Run All Tests" Coverage

The **▶️ Run All Tests** button executes 9 comprehensive tests:
1. Query active tab
2. Query all tabs
3. Get current tab (handles popup context correctly)
4. Create new tab
5. Update tab URL
6. Reload tab
7. Get tab by ID
8. Remove tab
9. Verify event listeners are working

## 🚀 Installation

1. Open Nook browser
2. Navigate to the extensions page
3. Enable "Developer Mode"
4. Click "Load Unpacked Extension"
5. Select the `test-extensions/03-tabs-test/` directory
6. The extension icon (📑) should appear in your toolbar

## 📖 Usage

### Quick Test (Recommended)

1. Click the extension icon (📑) in the toolbar
2. Click the **▶️ Run All Tests** button
3. Wait 3-5 seconds for all tests to complete
4. Review the comprehensive results

**Expected Output:**
```
🎉 ALL TESTS PASSED!

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
RESULTS: 9/9 tests passed (100.0%)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ tabs.query() active: PASS
✅ tabs.query() all: PASS
✅ tabs.getCurrent(): PASS
✅ tabs.create(): PASS
✅ tabs.update(): PASS
✅ tabs.reload(): PASS
✅ tabs.get(): PASS
✅ tabs.remove(): PASS
✅ Event listeners: PASS
```

### Individual Tests

For detailed testing or debugging, use the individual test buttons:

- **Query Active Tab** - Get information about the currently active tab
- **Query All Tabs** - List all open tabs
- **Get Current Tab** - Test getCurrent() (expected to return undefined in popup)
- **Create New Tab** - Open a new tab with example.com
- **Update Tab URL** - Navigate the active tab to example.org
- **Reload Tab** - Refresh the active tab
- **Close Tab** - Create and immediately close a tab
- **Test Events** - View event listener statistics

### Background Console Logs

The extension logs detailed information to the console:

1. Click "Open Console" button in the popup, or
2. Right-click the extension icon > Inspect Extension
3. Look for logs prefixed with `📑 [Background]`

**Example Console Output:**
```
📑 [Background] Tab created: {id: 123, url: "https://example.com", active: false}
📑 [Background] Tab updated: {id: 123, status: "loading"}
📑 [Background] Tab activated: {tabId: 123, windowId: 1}
📑 [Background] Tab removed: {id: 123}
```

## 🐛 Troubleshooting

### Test Failures

**tabs.query() fails:**
- Check that the extension has the "tabs" permission
- Verify that tabs actually exist in the browser

**tabs.create() fails:**
- Check browser console for errors
- Verify the browser can open new tabs

**tabs.getCurrent() returns unexpected:**
- This is expected behavior in popup context
- getCurrent() typically only works in tab contexts

**Event listeners not working:**
- Check the background service worker is running
- Look for errors in the background console
- Try reloading the extension

### Performance Notes

- Tests create and close tabs automatically
- Each test waits 500ms between operations for stability
- Total "Run All Tests" execution time: ~3-5 seconds
- Event listeners run continuously in the background

## 📊 Expected Results

### Full API Implementation

If the Tabs API is fully implemented, you should see:
- ✅ **100% pass rate** (9/9 tests)
- All tests show green checkmarks
- Event counters increment as tabs are created/modified
- No errors in console

### Partial Implementation

If some APIs are missing:
- ⚠️ Some tests will fail with specific error messages
- Check which APIs are failing
- Review console for implementation hints

### Common Failure Patterns

**"tabs.create is not a function"** → Tab creation not implemented
**"tabs.query is not a function"** → Tab querying not implemented
**"No response from background"** → Background event listeners not working

## 🔍 What This Tests

### Query Functionality
- Can retrieve active tab
- Can list all tabs
- Can filter tabs by properties
- Returns correct tab objects with id, url, title, etc.

### Tab Lifecycle
- Can create new tabs
- Can update tab properties
- Can reload tabs
- Can close tabs
- Returns correct tab objects after operations

### Event System
- Background script receives tab events
- Event listeners fire correctly
- Event data contains expected properties
- Events fire in correct order

## 📝 Notes

- **tabs.getCurrent()** is expected to return `undefined` in popup context
- Tests create/remove tabs automatically - this is intentional
- Event counters persist for the lifetime of the extension
- Background service worker must be running for event tests to work

## 🎓 Learning

This test extension demonstrates:
- Async/await patterns for Tab API calls
- Proper error handling for API failures
- Event listener setup in background scripts
- Message passing between popup and background
- Tab lifecycle management
- Context-aware API behavior (popup vs tab context)

## 🚦 Success Criteria

**✅ Implementation is working correctly if:**
- All 9 tests pass (100%)
- Tabs are created/removed successfully
- Event listeners track all tab activities
- Console shows detailed event logs
- No JavaScript errors occur

**⚠️ Needs attention if:**
- Any tests fail
- Event counters don't increment
- Console shows errors
- Tabs don't open/close as expected

---

**Built with ❤️ for Nook Browser Extension Testing**

