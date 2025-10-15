# Extension Testing Guide for Nook Browser

## Overview

This document provides a comprehensive guide to testing Chrome Extension API compatibility in Nook browser using the test extension suite located in `test-extensions/`.

## Quick Start

### 1. Install Test Extensions

**In Nook Browser:**
1. Open Nook
2. Navigate to Settings → Extensions (or the extension management UI)
3. Click "Install from Folder" or "Load Unpacked Extension"
4. Navigate to `test-extensions/01-runtime-test/`
5. Click "Select" to install

Repeat for other test extensions (`02-storage-test/`, etc.)

### 2. View Test Results

**Open Developer Console:**
- Press `Cmd + Option + I` (macOS)
- Or: Right-click anywhere → "Inspect" → Console tab

**What to Look For:**
- Test output appears immediately when extension loads
- Look for emojis and markers:
  - `✅ PASS` - Test succeeded
  - `❌ FAIL` - Test failed
  - `⚠️  WARN` - Test passed with caveats
- Final success rate at the end

### 3. Run Interactive Tests

1. Click the extension icon in the browser toolbar
2. The popup will open with test buttons
3. Click buttons to run specific tests
4. Results appear in the popup UI

---

## Test Extensions

### 01-runtime-test (Runtime API Test)

**Purpose**: Validates `chrome.runtime.*` APIs

**Automatic Tests** (run on background script load):
- Extension ID availability
- Manifest retrieval
- Resource URL generation
- Message passing (sendMessage, onMessage)
- Event listeners (onInstalled, onStartup)
- Cross-context communication
- Rapid messaging stress test

**Interactive Tests** (popup):
- Runtime.id check
- GetManifest() inspection
- GetURL() for resources
- SendMessage to background
- Connect() for long-lived connections

**Expected Results:**
- All automatic tests should PASS
- Success rate: 90-100%
- Any failures indicate bugs in runtime implementation

**Common Issues:**
- "No response received" - Background script may not be running
- "Extension ID missing" - Critical runtime.id bug
- "Message timeout" - Message passing implementation issue

---

### 02-storage-test (Storage API Test)

**Purpose**: Validates `chrome.storage.local`, `chrome.storage.session`, and `chrome.storage.onChanged`

**Automatic Tests** (run on background script load):
- Local storage: set, get, remove, clear
- Session storage: set, get, remove, clear
- GetBytesInUse() for both storage areas
- onChanged event firing
- Large data storage (~100KB)
- Data integrity validation

**Interactive Tests** (popup):
- Write/read/clear local storage
- Write/read session storage
- Large data stress test
- Performance speed test
- Real-time storage statistics

**Expected Results:**
- Most tests should PASS
- Success rate: 80-95%
- getBytesInUse() may return 0 (not critical)
- Large data test should complete in <100ms

**Common Issues:**
- "getBytesInUse returns 0" - API may not be implemented (not critical)
- "Large data fails" - Storage quota issues
- "onChanged not firing" - Event system bug
- "Session data lost on popup close" - Session persistence issue

---

## Interpreting Test Results

### Success Indicators

```
✅ PASS: runtime.id is available
✅ PASS: getManifest() works correctly
📊 Success Rate: 9/9 (100%)
```

This means:
- All tests passed
- Implementation is working correctly
- No action needed

### Failure Indicators

```
❌ FAIL: sendMessage() no response
❌ ERROR: Uncaught TypeError: chrome.runtime.getManifest is not a function
📊 Success Rate: 7/9 (77.8%)
```

This means:
- 2 out of 9 tests failed
- Implementation has bugs that need fixing
- Check console for detailed error messages

### Warning Indicators

```
⚠️  WARN: getBytesInUse returns 0 (may not be implemented)
⚠️  WARN: No response received (popup may not be open)
```

This means:
- Test passed but with caveats
- Feature may be partially implemented
- Not necessarily a blocker

---

## Test Results Documentation

### Template for Reporting Results

When testing, document results using this template:

```markdown
## Test Results - [Extension Name]

**Date**: [YYYY-MM-DD]
**Nook Version**: [Version]
**macOS Version**: [Version]
**Test Extension**: [Name and version]

### Automatic Tests
- **Success Rate**: X/Y (Z%)
- **Pass**: [List of passed tests]
- **Fail**: [List of failed tests]
- **Warn**: [List of warnings]

### Interactive Tests
- **Test 1 Name**: ✅ PASS / ❌ FAIL
- **Test 2 Name**: ✅ PASS / ❌ FAIL
  ...

### Console Output
```
[Paste full console output here]
```

### Issues Found
1. **Issue Name**
   - Description: [What failed]
   - Expected: [What should happen]
   - Actual: [What actually happened]
   - Reproducible: Yes/No
   - Severity: Critical/High/Medium/Low

### Screenshots
[Attach screenshots if relevant]
```

---

## Next Steps After Testing

### If All Tests Pass (90%+ success rate)
✅ **Great!** The API is well-implemented.
- Document which APIs work
- Move to testing real extensions
- Note any minor warnings for future improvement

### If Most Tests Pass (70-90% success rate)
⚠️ **Good but needs work**
- Document which specific tests fail
- File bugs for each failure
- Determine if failures block real extensions
- Prioritize fixes based on impact

### If Many Tests Fail (<70% success rate)
❌ **Needs significant work**
- Core API implementation has issues
- Review implementation code
- Fix critical bugs before testing real extensions
- May need to refactor parts of ExtensionManager

---

## Advanced Testing

### Performance Benchmarks

Expected performance on modern Mac:
- **Runtime.sendMessage**: <5ms round-trip
- **Storage.local.set**: <10ms for small data
- **Storage.local.get**: <5ms
- **Large data (100KB)**: <50ms
- **100 rapid messages**: <500ms total

If performance is significantly slower:
- Check for blocking operations
- Review async handling
- Profile with Instruments

### Stress Testing

Test extensions include stress tests:
- **Rapid messaging**: 10-100 messages in quick succession
- **Large data**: 50-100KB storage operations
- **Many operations**: 100+ sequential operations

These help identify:
- Race conditions
- Memory leaks
- Performance bottlenecks
- Async handling issues

---

## Troubleshooting

### Extension Won't Install
- Check manifest.json validity
- Ensure all referenced files exist
- Check console for install errors
- Verify icon files are valid PNGs

### Tests Don't Run
- Check if background script loaded
- Look for JavaScript errors in console
- Verify chrome.* APIs are available
- Check if extension is enabled

### Console Shows Nothing
- Extension may not have loaded
- Background script may have crashed
- Check extension is enabled in settings
- Try reloading the extension

### Tests Timeout
- Increase timeout values in code
- Check for blocking operations
- Verify async callbacks are called
- Look for promise rejections

---

## Contributing Test Results

When you test the extensions, please share results:

1. **Run the tests** following this guide
2. **Document results** using the template above
3. **File issues** for any failures on GitHub
4. **Share findings** in team Slack/Discord/etc.

Your test results help:
- Identify bugs early
- Track implementation progress
- Prioritize development efforts
- Ensure quality before launch

---

## FAQ

**Q: Do I need to test all extensions?**
A: Start with 01-runtime-test and 02-storage-test. These cover the most critical APIs.

**Q: How long does testing take?**
A: Automatic tests run in seconds. Interactive tests take 5-10 minutes per extension.

**Q: What if I find a bug?**
A: Document it using the template above and file a GitHub issue with the console output.

**Q: Can I modify the test extensions?**
A: Yes! Feel free to add more tests or improve existing ones. PRs welcome!

**Q: Are these tests comprehensive?**
A: They cover the happy path and common edge cases. Real extensions may expose additional issues.

**Q: What's the minimum passing rate for launch?**
A: Target 90%+ for critical APIs (runtime, storage). Lower rates acceptable for less common APIs.

---

## Resources

- [Test Extensions Directory](../test-extensions/)
- [Chrome Extension API Docs](https://developer.chrome.com/docs/extensions/reference/)
- [WKWebExtension Documentation](https://developer.apple.com/documentation/webkitextensions)
- [Nook Extension Manager Implementation](../Nook/Managers/ExtensionManager/)

---

**Last Updated**: October 15, 2025
**Document Version**: 1.0

