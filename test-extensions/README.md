# WebExtension Test Suite

This directory contains test extensions for validating Nook's WebExtension implementation.

## Test Extensions

### 1. test-message-passing
Tests the critical `runtime.sendMessage` API for communication between popup and background scripts.

**Features:**
- Send messages from popup to background
- Receive responses from background
- Test `chrome.tabs.query()` API

**Usage:**
1. Load the extension in Nook
2. Click the extension icon to open popup
3. Click "Send Message to Background" button
4. Should see a success response if message passing works

### 2. test-storage
Tests the `chrome.storage.local` API for persistent data storage.

**Features:**
- Save key-value pairs to storage
- Load values by key
- Get all stored data
- Clear all storage

**Usage:**
1. Load the extension in Nook
2. Click the extension icon to open popup
3. Enter a key and value, click "Save to Storage"
4. Click "Load from Storage" or "Get All Storage" to verify

### 3. test-tab-events
Tests tab lifecycle event listeners in background scripts.

**Features:**
- Monitor `chrome.tabs.onCreated`
- Monitor `chrome.tabs.onUpdated`
- Monitor `chrome.tabs.onActivated`
- Monitor `chrome.tabs.onRemoved`

**Usage:**
1. Load the extension in Nook
2. Create, switch, or close tabs
3. Click the extension icon and "Refresh Event Log"
4. Should see captured tab events

### 4. test-content-script
Tests content script injection into web pages.

**Features:**
- Auto-inject content script on all pages
- Visual indicator when content script loads
- Message passing between popup and content script
- `chrome.tabs.sendMessage()` API test

**Usage:**
1. Load the extension in Nook
2. Navigate to any webpage
3. Should see a green "Content Script Loaded" indicator appear briefly
4. Click the extension icon and "Ping Current Tab Content Script"
5. Should receive a response from the content script

## Loading Test Extensions

1. Open Nook
2. Navigate to Extensions settings (or use developer menu)
3. Enable "Developer Mode" if required
4. Click "Load Unpacked Extension"
5. Select one of the test-extensions subdirectories

## Expected Results

✅ **Working correctly:**
- Popups should open and display UI
- Console logs should appear in Xcode/terminal
- Buttons should be clickable and functional

❌ **Known issues (to be fixed):**
- `runtime.sendMessage` may not work (message passing not implemented)
- `chrome.storage.local` may not work (storage API not implemented)
- Tab events may not fire reliably
- Content script injection timing issues

## Development Notes

These test extensions use Manifest V3 format and Chrome extension APIs. They help identify which WebExtension APIs need implementation or fixes in Nook.

Check the console output (Xcode or terminal running Nook) for detailed logging from both the extension side and the Nook side.

