# Smart Shortcut System Usage

## Overview
The smart shortcut system prevents conflicts between Nook's keyboard shortcuts and web app shortcuts by detecting when web apps consume shortcuts and offering a "press again" mechanism.

## How It Works

### 1. Detection Process
- When a keyboard shortcut that matches a Nook action is pressed, the system checks if it's a common web app shortcut
- For web app shortcuts (like ⌘S for save), the first press is allowed to pass through to the web app
- The system waits briefly to see if the web app consumes the shortcut

### 2. Double-Press Mechanism
- If a web app shortcut is detected, a toast appears saying "Press ⌘S again to save" (or similar)
- Within 15 seconds, pressing the same shortcut again will execute Nook's action instead
- The toast auto-hides after 3 seconds

### 3. Supported Shortcuts
The system currently detects conflicts for these common web app shortcuts:
- ⌘R (Refresh) - Used by many web apps for reload/save
- ⌘S (Save) - Common in web-based document editors
- ⌘T (New Tab) - Some web apps use this for new documents
- ⌘W (Close) - Some web apps use this for close/save
- ⌘C (Copy) - Used by web apps with custom copy behavior
- ⌘[ and ⌘] (Back/Forward) - Used by some web apps for navigation

## Example Scenarios

### Google Sheets
1. User presses ⌘S in Google Sheets
2. Google Sheets saves the document (first press goes to web app)
3. Toast appears: "Press ⌘S again to save"
4. User presses ⌘S again within 15 seconds
5. Nook's save action executes (if applicable)

### Figma/Draw.io
1. User presses ⌘S in Figma
2. Figma saves the design (first press goes to web app)
3. Toast appears: "Press ⌘S again to save"
4. If user wants Nook's action instead, they press ⌘S again

## Benefits
- No conflicts with web app shortcuts
- Users can still access Nook functionality when needed
- Clear visual feedback about how to access Nook actions
- Graceful fallback to normal behavior

## Technical Details
- Uses `@Observable` pattern for state management
- Integrates with existing `KeyboardShortcutManager`
- Toast UI appears in top-right corner with other notifications
- 15-second window for double-press detection
- Automatic cleanup of timers and state

## Configuration
The system can be extended to support additional shortcuts by modifying the `isWebAppShortcutCandidate` method in `SmartShortcutManager.swift`.