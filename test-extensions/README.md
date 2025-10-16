# Nook Browser Extension Test Suite

This directory contains comprehensive test extensions to validate the Chrome Extension API implementation in Nook browser.

## 🎯 Purpose

These test extensions serve multiple purposes:
1. **Validation**: Verify that implemented APIs work correctly
2. **Debugging**: Identify bugs and edge cases in the implementation
3. **Documentation**: Demonstrate how each API should be used
4. **Regression Testing**: Ensure future changes don't break existing functionality
5. **Compatibility Baseline**: Establish what percentage of extensions can work today

## 📦 Test Extensions

### 1. Runtime API Test (`01-runtime-test/`)
Tests `chrome.runtime.*` APIs across all contexts (background, content, popup).

**Covers:**
- Message passing (sendMessage, onMessage)
- Long-lived connections (connect, Port)
- Extension information (id, getManifest, getURL)
- Event listeners (onInstalled, onStartup)
- Cross-context communication
- Rapid messaging stress tests

**Status:** ✅ Complete

---

### 2. Storage API Test (`02-storage-test/`)
Tests `chrome.storage.local`, `chrome.storage.session`, and `chrome.storage.onChanged`.

**Covers:**
- Read/write operations
- Data type support (primitives, objects, arrays)
- Storage limits and large data
- getBytesInUse()
- Change events
- Performance benchmarks

**Status:** ✅ Complete

---

### 3. Tabs API Test (`03-tabs-test/`) - Coming Soon
Will test `chrome.tabs.*` APIs.

**Will cover:**
- Tab queries
- Tab creation/updates/removal
- Tab properties (URL, title, etc.)
- Tab messaging
- Multiple windows

**Status:** 📋 Planned

---

### 4. Tier 1 APIs Test (`04-tier1-apis-test/`)
Comprehensive test for all Tier 1 Chrome Extension APIs.

**Covers:**
- **chrome.action**: Toolbar icon, badge, popup, click events
- **chrome.contextMenus**: Parent/submenu items, separators, click handlers
- **chrome.notifications**: Basic/button notifications, events (click, close)
- **chrome.commands**: Keyboard shortcuts, getAll(), onCommand events

**Keyboard Shortcuts:**
- `Ctrl+Shift+Y` - Test command (shows notification)
- `Ctrl+Shift+N` - Advanced notification with buttons
- `Ctrl+Shift+U` - Execute action (open popup)

**Features:**
- Interactive popup with test controls
- Background service worker with all APIs
- Right-click context menus
- Native system notifications
- Full event handling for all APIs

**Status:** ✅ Complete

---

## 🚀 Installation

### Option 1: Install Individual Test Extension
1. Open Nook browser
2. Navigate to extension settings
3. Click "Load Unpacked" or "Install from folder"
4. Select one of the test extension directories (e.g., `01-runtime-test/`)

### Option 2: Install All Test Extensions
```bash
# If Nook supports batch installation
for dir in test-extensions/*/; do
  # Install $dir
done
```

## 📊 Running Tests

### Automatic Tests
Most test extensions run automatically when loaded:
- Background scripts execute tests on startup
- Results are logged to the browser console
- Success/failure indicators clearly marked

**To view results:**
1. Open Developer Console (Cmd+Option+I)
2. Look for test output with ✅ PASS or ❌ FAIL markers
3. Check for overall success rate at the end

### Interactive Tests
Some tests require user interaction via the popup:
1. Click the extension icon in the toolbar
2. Click test buttons to run specific scenarios
3. Results appear in the popup UI

## 📝 Interpreting Results

### Success Indicators
- `✅ PASS` - Test passed successfully
- `✅ SUCCESS` - Operation completed correctly
- `📊 Success Rate: X/Y` - Overall test suite performance

### Failure Indicators
- `❌ FAIL` - Test failed
- `❌ ERROR` - Exception or critical error
- `⚠️  WARN` - Test passed but with caveats

### Common Warnings
- **"No response received"**: May indicate async timing issues or missing message handlers
- **"getBytesInUse returns 0"**: API may not be fully implemented
- **"Tab not found"**: Content script communication issues

## 🎯 Expected Results

### Current Implementation (as of branch: feature/webextension-support)
Based on the code analysis, we expect:

- **Runtime API**: 90-100% pass rate (core functionality implemented)
- **Storage API**: 80-90% pass rate (getBytesInUse may be partial)
- **Tabs API**: TBD (tests not yet created)
- **Scripting API**: TBD (tests not yet created)

## 🐛 Reporting Issues

If you find a test failure:

1. **Capture the Console Output**
   - Full console log from extension load to test completion
   - Look for error messages and stack traces

2. **Document the Issue**
   - Which test extension?
   - Which specific test failed?
   - Expected vs actual behavior
   - Steps to reproduce

3. **Check for Known Limitations**
   - Review the extension's README for known issues
   - Some failures may be documented limitations of WKWebExtension

4. **File a Bug Report**
   - Include console output
   - Include test extension version
   - Include Nook browser version and macOS version

## 📖 Test Extension Development

### Creating a New Test Extension

1. **Create directory**: `test-extensions/XX-apiname-test/`
2. **Required files**:
   - `manifest.json` - Extension manifest
   - `background.js` - Automatic tests
   - `popup.html` / `popup.js` - Interactive tests
   - `README.md` - Documentation
   - `icon16.png`, `icon48.png`, `icon128.png` - Icons

3. **Test Structure**:
```javascript
// Run tests sequentially
async function runAllTests() {
  console.log('=== TEST SUITE START ===');
  
  await test1();
  await test2();
  // ...
  
  console.log('=== TEST SUITE COMPLETE ===');
  console.log('Success Rate: X/Y');
}
```

4. **Naming Conventions**:
   - Test functions: `testFeatureName()`
   - Console output: Use emojis and clear markers (✅, ❌, ⚠️)
   - Results: Log both successes and failures

## 🔬 Advanced Testing

### Performance Testing
Some tests include performance benchmarks:
- Measure operation latency
- Test throughput (ops/second)
- Identify performance bottlenecks

### Stress Testing
Tests that push limits:
- Rapid message firing
- Large data storage
- Many concurrent operations

### Edge Cases
Tests specifically designed to catch bugs:
- Null/undefined values
- Empty arrays/objects
- Very long strings
- Nested data structures

## 📚 Reference

- [Chrome Extension API Docs](https://developer.chrome.com/docs/extensions/reference/)
- [WKWebExtension Documentation](https://developer.apple.com/documentation/webkitextensions)
- [Nook Extension Manager Implementation](../Nook/Managers/ExtensionManager/)

## 🤝 Contributing

To add new test extensions:
1. Follow the directory structure and naming conventions
2. Include comprehensive README
3. Test both happy path and edge cases
4. Document expected results and known limitations
5. Update this main README with your test extension info

---

## 📊 Overall Test Status

| API Category | Test Extension | Status | Coverage |
|--------------|---------------|--------|----------|
| Runtime      | 01-runtime-test | ✅ Complete | 90% |
| Storage      | 02-storage-test | ✅ Complete | 85% |
| Tabs         | 03-tabs-test | 📋 Planned | 0% |
| Scripting    | 04-scripting-test | 📋 Planned | 0% |
| Commands     | 05-commands-test | 📋 Planned | 0% |
| Action       | TBD | 📋 Future | 0% |
| WebNavigation| TBD | 📋 Future | 0% |
| ContextMenus | TBD | 📋 Future | 0% |
| Notifications| TBD | 📋 Future | 0% |

**Last Updated:** October 15, 2025
