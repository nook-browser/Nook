# WebExtension Testing Guide for Nook

This directory contains test extensions to verify WebExtension API implementation in Nook browser.

## Test Extensions

### 1. test-message-passing
**Purpose**: Test `chrome.runtime.sendMessage` API between popup and background script

**What it tests**:
- Background script loading and initialization
- Message passing from popup to background
- Response handling from background to popup
- Error handling for failed messages

**How to use**:
1. Install the extension in Nook
2. Click the extension icon to open the popup
3. Check the browser console for diagnostic logs
4. Look for these key messages:
   - `✅ Background script loaded` - Background is ready
   - `📨 Received message from popup` - Background received the message
   - `✅ sendMessage SUCCESS` - Popup received response

**Expected behavior**:
- Popup should show "Response from background" with timestamp
- Console should show successful round-trip message exchange
- No timeout warnings after 2 seconds

### 2. test-storage
**Purpose**: Test `chrome.storage.local` API

**What it tests**:
- Storing data with `chrome.storage.local.set`
- Retrieving data with `chrome.storage.local.get`
- Data persistence across sessions
- Storage change listeners

**How to use**:
1. Install the extension
2. Click the extension icon
3. Click "Save Data" button
4. Refresh the popup
5. Data should still be displayed

### 3. test-tab-events
**Purpose**: Test tab lifecycle events

**What it tests**:
- `chrome.tabs.onCreated`
- `chrome.tabs.onUpdated`
- `chrome.tabs.onActivated`
- `chrome.tabs.onRemoved`

**How to use**:
1. Install the extension
2. Open the background script console
3. Create, switch, and close tabs
4. Watch for event notifications

### 4. test-content-script
**Purpose**: Test content script injection

**What it tests**:
- Content script injection on page load
- DOM access from content scripts
- Message passing from content script to background

**How to use**:
1. Install the extension
2. Navigate to any web page
3. Look for red border around the page
4. Check console for content script messages

## Debugging Tips

### For runtime.sendMessage issues

**Symptom**: Timeout warnings after 2 seconds

**Possible causes**:
1. Background script not loaded
   - Check for `✅ Background content loaded successfully`
   - Verify extension has background script in manifest

2. No onMessage listener registered
   - Check background script has `chrome.runtime.onMessage.addListener`
   - Verify background script is actually executing (add console.log)

3. Extension controller not shared
   - Both popup and background need same WKWebExtensionController
   - Check logs for `webExtensionController: ✅`

**Fix checklist**:
- [ ] `extensionContext.loadBackgroundContent()` called
- [ ] Background script logs appear in console
- [ ] Popup has `webExtensionController` set
- [ ] Background has `onMessage` listener registered

### For storage API issues

**Symptom**: Data not persisting

**Possible causes**:
1. Storage API not implemented
2. Data store not configured for extension
3. Permission not granted

### For tab events issues

**Symptom**: Events not firing

**Possible causes**:
1. Tab adapter not configured
2. Extension doesn't have `tabs` permission
3. Event listeners not registered properly

## Implementation Status

| API | Status | Notes |
|-----|--------|-------|
| `runtime.sendMessage` | 🟡 In Progress | Framework should support, needs verification |
| `runtime.onMessage` | 🟡 In Progress | Requires background script support |
| `storage.local` | ❌ Not Implemented | Needs implementation |
| `tabs.query` | ✅ Implemented | Basic support exists |
| `tabs.onCreated` | ✅ Implemented | Event system in place |
| Content Scripts | ✅ Implemented | Injection working |

## Console Output Guide

### Good Output Example
```
🔧 [ExtensionManager] Loading background content...
✅ [ExtensionManager] Background content loaded successfully!
📢 [Background] Script loaded and ready
📤 [Popup] Attempting runtime.sendMessage...
📨 [Background] Received message from popup
✅ [Popup] sendMessage SUCCESS! Round trip: 45ms
```

### Problem Output Example
```
🔧 [ExtensionManager] Loading background content...
❌ [ExtensionManager] Failed to load background content
📤 [Popup] Attempting runtime.sendMessage...
⏱️ [Popup] sendMessage timeout - no response after 2 seconds
```

## Next Steps

1. Install test-message-passing extension
2. Review console output for diagnostic messages
3. If runtime.sendMessage works: Move to storage API tests
4. If runtime.sendMessage fails: Debug background script loading
5. Document any issues found in GitHub

## Architecture Notes

### Message Passing Flow

```
Popup (webkit-extension://ID/popup.html)
  ↓ chrome.runtime.sendMessage()
  ↓
WKWebExtensionController (routes message)
  ↓
Background Script (loaded via loadBackgroundContent())
  ↓ chrome.runtime.onMessage listener
  ↓ sendResponse() callback
  ↓
WKWebExtensionController (routes response)
  ↓
Popup (receives response in callback)
```

### Key Requirements

1. **Shared Controller**: Both contexts must use same WKWebExtensionController
2. **Background Loaded**: `loadBackgroundContent()` must complete successfully
3. **Listener Registered**: Background must call `addListener` before message sent
4. **Proper Timing**: Background needs time to initialize before receiving messages

### Common Pitfalls

- ❌ Creating separate WKWebViewConfiguration for popup
- ❌ Not waiting for background script to load
- ❌ Missing onMessage listener in background script
- ❌ Using wrong extension context for popup WebView

## Further Reading

- [Chrome Extensions: Messaging API](https://developer.chrome.com/docs/extensions/mv3/messaging/)
- [WebKit Web Extensions](https://developer.apple.com/documentation/safariservices/safari_web_extensions)
- [WKWebExtensionController Documentation](https://developer.apple.com/documentation/webkit/wkwebextensioncontroller)

