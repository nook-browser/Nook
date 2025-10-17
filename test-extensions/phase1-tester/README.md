# Phase 1 Tester Extension

Comprehensive test suite for validating Phase 1 implementation of Chrome extension support in Nook browser.

## 🎯 Purpose

This extension thoroughly tests all functionality implemented in Phase 1:

- **Task 1.1**: MessagePort Management (`runtime.connect()`)
- **Task 1.2**: Runtime Messaging with Real Responses (`runtime.sendMessage()`)
- **Task 1.3**: Commands Event Delivery (keyboard shortcuts)
- **Task 1.3**: Context Menus Event Delivery (right-click menus)

## 📦 Installation

1. Open Nook browser
2. Go to Extensions management (typically `nook://extensions` or similar)
3. Enable "Developer mode"
4. Click "Load unpacked extension"
5. Select the `phase1-tester` folder

## 🧪 Test Scenarios

### Task 1.1: MessagePort Management

**What it tests:**
- Port connection establishment via `chrome.runtime.connect()`
- Bidirectional message passing through ports
- Port lifecycle (connection, messaging, disconnection)
- Port storage and retrieval in ExtensionManager

**How to test:**
1. Open the extension popup
2. Click "Connect Port" button
3. Verify status changes to "Active"
4. Click "Send Port Message" multiple times
5. Check console logs for port messages
6. Click "Disconnect Port"
7. Verify status returns to "Pending"

**Expected behavior:**
- ✅ Port connects successfully
- ✅ Messages sent through port are received by background
- ✅ Background echoes messages back through same port
- ✅ Message count increments correctly
- ✅ Port disconnects cleanly

**What to look for in logs:**
```
✅ [Task 1.1] Port connected: popup-test-port
📨 [Task 1.1] Message received on port "popup-test-port": {...}
❌ [Task 1.1] Port disconnected: popup-test-port
```

### Task 1.2: Runtime Messaging

**What it tests:**
- One-time messages via `chrome.runtime.sendMessage()`
- Real response routing (not synthetic `{success: true}`)
- Message ID tracking and response matching
- Timeout handling for hung requests
- Thread-safe response tracking

**How to test:**

#### Test 1: Simple Ping
1. Click "Send Ping" button
2. Verify response is received with "pong" type
3. Check latency is shown (should be < 100ms)

#### Test 2: Get Data
1. Click "Get Data" button
2. Verify response contains actual data (not just `{success: true}`)
3. Response should include:
   - `testValue`: "Phase 1 is working!"
   - `timestamp`
   - `randomValue`

#### Test 3: Storage Test
1. Click "Storage Test" button
2. Verify data is stored and retrieved
3. Response should include stored data

#### Test 4: Round Trip Test
1. Click "Round Trip Test" button
2. Verify complete round-trip with storage
3. Check latency measurement

**Expected behavior:**
- ✅ All messages receive REAL responses (not synthetic)
- ✅ Response data matches expected structure
- ✅ Latency is measured and displayed
- ✅ Message and response counts increment
- ✅ Status badge shows "Pass" (not "Fail")

**What to look for in logs:**
```
📬 [Task 1.2] Runtime message received: {...}
🏓 [Task 1.2] Ping received, sending pong...
📊 [Task 1.2] Data request received, fetching...
```

**Critical validation:**
- ⚠️ If you see "WARNING: Received synthetic success response", Task 1.2 is NOT working correctly
- ✅ Real responses will have multiple fields with actual data

### Task 1.3: Commands (Keyboard Shortcuts)

**What it tests:**
- Keyboard command registration
- Command event delivery to background service worker
- Event data structure matches `chrome.commands.onCommand`
- MessagePort broadcasting of command events

**How to test:**
1. Make sure Nook has focus
2. Press keyboard shortcuts:
   - **Cmd+Shift+1** (Mac) or **Ctrl+Shift+1** (Windows/Linux)
   - **Cmd+Shift+2**
   - **Cmd+Shift+3**
3. Watch the "Commands" section in popup
4. Click "Refresh Command History" to see triggered commands

**Expected behavior:**
- ✅ Each keyboard shortcut triggers `chrome.commands.onCommand` event
- ✅ Command name is correctly passed to background
- ✅ Events are logged in command history
- ✅ Trigger count increments
- ✅ Last command is updated

**What to look for in logs:**
```
⌨️ [Task 1.3] Command triggered: {
  command: "test-command-1",
  triggerCount: 1,
  timestamp: ...
}
```

**On page (content script):**
- You should see a notification appear when a command is triggered

### Task 1.3: Context Menus (Right-Click Menus)

**What it tests:**
- Context menu item registration
- Click event delivery to background service worker
- Event data structure matches `chrome.contextMenus.onClicked`
- MessagePort broadcasting of menu clicks

**How to test:**
1. Navigate to any web page in Nook
2. Right-click on the page
3. Look for "Test Menu Item 1" and "Test Menu Item 2" in context menu
4. Click on one of the test menu items
5. Return to extension popup
6. Click "Refresh Menu History"

**Expected behavior:**
- ✅ Test menu items appear in context menu
- ✅ Clicking a menu item triggers `chrome.contextMenus.onClicked` event
- ✅ Event includes menuItemId, pageUrl, and other context
- ✅ Menu click history shows triggered items
- ✅ Click count increments

**What to look for in logs:**
```
🖱️ [Task 1.3] Context menu clicked: {
  menuItemId: "test-menu-1",
  clickCount: 1,
  pageUrl: "https://example.com",
  timestamp: ...
}
```

**On page (content script):**
- You should see a notification appear when a menu item is clicked

## 🔍 Content Script Tests

The extension also injects a content script that:

1. Shows a visual indicator (top-right corner: "🧪 Phase 1 Tester Active")
2. Establishes its own MessagePort connection
3. Receives broadcast messages from background (commands, menu clicks)
4. Can send test messages by clicking the indicator

**How to test:**
1. Navigate to any web page
2. Look for the purple indicator in top-right corner
3. Click the indicator to send a test message
4. Watch for success notification
5. Trigger commands or menu clicks to see broadcast notifications

## 📊 Success Criteria

### Task 1.1: MessagePort Management
- [ ] Port connects successfully
- [ ] Messages flow bidirectionally through port
- [ ] Port disconnects cleanly
- [ ] Multiple ports can coexist (popup + content script)

### Task 1.2: Runtime Messaging
- [ ] Messages reach background service worker
- [ ] **REAL responses** are received (not synthetic)
- [ ] Response data structure is correct
- [ ] Latency is measured accurately
- [ ] No "synthetic success" warnings appear

### Task 1.3: Commands
- [ ] Keyboard shortcuts trigger events
- [ ] Event data structure is correct
- [ ] Events are logged in storage
- [ ] Content scripts receive broadcast

### Task 1.3: Context Menus
- [ ] Menu items appear in context menu
- [ ] Clicks trigger events correctly
- [ ] Event data includes page context
- [ ] Events are logged in storage
- [ ] Content scripts receive broadcast

## 🐛 Debugging

If tests fail, check:

1. **Console Logs**: Open browser console and extension background console
2. **Network Tab**: Check for WebSocket connections (MessagePort)
3. **Storage**: Inspect `chrome.storage.local` contents
4. **Timing**: Watch for timeout errors (10-second limit on responses)

### Common Issues

**Task 1.1 fails:**
- Check if `webExtensionController(_:connectUsing:for:completionHandler:)` delegate is implemented
- Verify ports are stored in `extensionMessagePorts` dictionary
- Check port lifecycle management

**Task 1.2 fails:**
- Look for "synthetic success" warning
- Verify `pendingMessageResponses` tracking is working
- Check if `webExtensionController(sendMessage:...)` delegate routes responses
- Ensure message IDs are tracked correctly

**Task 1.3 Commands fails:**
- Verify keyboard shortcuts are registered
- Check if `getBackgroundPort()` returns valid port
- Ensure command events are formatted correctly

**Task 1.3 Context Menus fails:**
- Verify menu items are created successfully
- Check if click events reach background
- Ensure menu event format matches Chrome API

## 📝 Test Results Template

```
=== Phase 1 Test Results ===

Task 1.1 - MessagePort Management: [PASS/FAIL]
- Port connection: [✅/❌]
- Bidirectional messaging: [✅/❌]
- Port disconnection: [✅/❌]
- Multiple ports: [✅/❌]

Task 1.2 - Runtime Messaging: [PASS/FAIL]
- Ping test: [✅/❌]
- Get data test: [✅/❌]
- Storage test: [✅/❌]
- Round trip test: [✅/❌]
- Real responses (no synthetic): [✅/❌]

Task 1.3 - Commands: [PASS/FAIL]
- Cmd+Shift+1: [✅/❌]
- Cmd+Shift+2: [✅/❌]
- Cmd+Shift+3: [✅/❌]
- Event broadcasting: [✅/❌]

Task 1.3 - Context Menus: [PASS/FAIL]
- Menu items visible: [✅/❌]
- Click event delivery: [✅/❌]
- Event data correct: [✅/❌]
- Event broadcasting: [✅/❌]

Overall Phase 1 Status: [PASS/FAIL]
```

## 🚀 Next Steps

After Phase 1 passes all tests:
- Move to Phase 2 (Content Script Native Injection)
- Test with real extensions (Dark Reader, etc.)
- Implement advanced features (frames, storage.sync, etc.)

## 📄 License

This is a test extension for development purposes only.

