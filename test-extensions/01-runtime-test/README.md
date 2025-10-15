# Runtime API Test Extension

## Purpose
Tests the implementation of `chrome.runtime.*` APIs in Nook browser.

## APIs Tested

### Background Script Tests:
- ✅ `chrome.runtime.id` - Extension ID availability
- ✅ `chrome.runtime.getManifest()` - Manifest retrieval
- ✅ `chrome.runtime.getURL()` - Resource URL generation
- ✅ `chrome.runtime.sendMessage()` - Message sending
- ✅ `chrome.runtime.onMessage` - Message receiving
- ✅ `chrome.runtime.onInstalled` - Install event
- ✅ `chrome.runtime.onStartup` - Startup event
- ✅ Background → Content script messaging
- ✅ Rapid fire messaging (stress test)

### Content Script Tests:
- ✅ `chrome.runtime.id` in content script context
- ✅ `chrome.runtime.sendMessage()` from content to background
- ✅ `chrome.runtime.onMessage` listener in content script
- ✅ `chrome.runtime.getURL()` in content script

### Popup Tests (Interactive):
- ✅ `chrome.runtime.id` in popup context
- ✅ `chrome.runtime.getManifest()` in popup
- ✅ `chrome.runtime.getURL()` in popup
- ✅ `chrome.runtime.sendMessage()` from popup to background
- ✅ `chrome.runtime.connect()` - Long-lived connections

## Installation

1. Open Nook browser
2. Navigate to extension settings
3. Click "Load Unpacked" or "Install from folder"
4. Select the `test-extensions/01-runtime-test` directory

## Usage

### Automatic Tests
When the extension loads, the background script automatically runs tests and logs results to the console.

### Interactive Tests
1. Click the extension icon in the toolbar to open the popup
2. Click each test button to run specific tests
3. Results will appear in the popup UI

### Viewing Results
Open the browser console (Cmd+Option+I) to see detailed test output with:
- ✅ PASS indicators for successful tests
- ❌ FAIL indicators for failed tests
- ⚠️  WARN indicators for tests that need attention

## Expected Results

All tests should PASS if the Runtime API is correctly implemented. Common issues:

- **"No response received"**: Background script may not be running or message handler not registered
- **"Tab not found"**: Content script communication issues
- **"Extension ID missing"**: Critical runtime.id issue that breaks many extensions

## Test Coverage

This extension validates:
- Cross-context communication (background ↔ popup ↔ content)
- Message passing reliability
- Event listener functionality
- Resource URL resolution
- Manifest data access
- High-frequency messaging stability

