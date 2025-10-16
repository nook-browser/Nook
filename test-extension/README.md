# Clipboard API Test Extension

A comprehensive test extension for validating the `navigator.clipboard` API implementation in Nook.

## Purpose

This extension tests the Clipboard API implementation required for password managers like Bitwarden to function properly.

## Features

### 📋 Test Suite

1. **API Detection**
   - Checks if `navigator.clipboard` exists
   - Verifies `writeText()` method availability
   - Verifies `readText()` method availability

2. **Write Test**
   - Tests `navigator.clipboard.writeText(text)`
   - Measures performance
   - Validates error handling

3. **Read Test**
   - Tests `navigator.clipboard.readText()`
   - Displays clipboard content
   - Handles empty clipboard gracefully

4. **Round Trip Test**
   - Writes test data to clipboard
   - Reads it back
   - Verifies data integrity

5. **Run All Tests**
   - Executes all tests in sequence
   - Provides summary of results
   - Logs detailed information to console

## Installation

1. Open Nook browser
2. Navigate to Extension Management
3. Enable Developer Mode
4. Click "Load Unpacked Extension"
5. Select the `test-extension` folder

## Usage

1. Click the extension icon in the toolbar
2. The test popup will open
3. Use individual test buttons or "Run All Tests"
4. Check results in the UI and console

## API Testing

### Write Test
```javascript
await navigator.clipboard.writeText("test text");
```

### Read Test
```javascript
const text = await navigator.clipboard.readText();
```

## Expected Behavior

✅ **Pass Criteria:**
- API methods exist and are functions
- writeText() successfully copies to system clipboard
- readText() successfully reads from system clipboard
- Round trip test preserves data integrity
- Operations complete in reasonable time (<100ms typical)

❌ **Fail Indicators:**
- API not available
- DOMException errors
- Data corruption in round trip
- Excessive latency

## Implementation Details

### Architecture
- Uses Promise-based async API (W3C Clipboard API spec)
- Timestamp-based callback system for native bridge
- WebKit message handlers for communication
- NSPasteboard for native macOS clipboard operations

### Native Bridge
Messages sent via `window.webkit.messageHandlers.chromeClipboard.postMessage()`

Response callbacks stored in `window.chromeClipboardCallbacks[timestamp]`

### Error Handling
Returns `DOMException` with type `NotAllowedError` on failures, per W3C spec.

## Debugging

Enable console logging to see detailed test execution:
- API detection results
- Operation timing
- Data verification
- Error messages

All logs prefixed with `[Clipboard Test]` for easy filtering.

## Bitwarden Usage Pattern

Bitwarden uses this API pattern:
```javascript
// Copy password to clipboard
await navigator.clipboard.writeText(password);

// Copy TOTP code
await navigator.clipboard.writeText(totpCode);

// Read clipboard content
const clipboardText = await navigator.clipboard.readText();
```

This test extension validates all these use cases.

