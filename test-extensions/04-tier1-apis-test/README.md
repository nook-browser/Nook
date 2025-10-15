# Tier 1 APIs Test Extension

A comprehensive test extension for all Tier 1 Chrome Extension APIs implemented in Nook.

## APIs Tested

This extension tests all four Tier 1 APIs:

1. **chrome.action** - Toolbar icon, badge, and popup
2. **chrome.contextMenus** - Right-click context menus
3. **chrome.notifications** - Native system notifications
4. **chrome.commands** - Keyboard shortcuts

## Features

### 🎯 chrome.action Tests
- ✅ Toolbar icon with popup
- ✅ Badge text and color updates
- ✅ Title changes
- ✅ Action click events
- ✅ Dynamic badge updates

### 📋 chrome.contextMenus Tests
- ✅ Parent menu items
- ✅ Submenu items
- ✅ Separator items
- ✅ Selection context menus
- ✅ Menu click handlers
- ✅ Dynamic menu updates

### 🔔 chrome.notifications Tests
- ✅ Basic notifications
- ✅ Notifications with buttons
- ✅ Notification priorities
- ✅ Context messages
- ✅ Click handlers
- ✅ Button click handlers
- ✅ Close handlers
- ✅ Clear notifications
- ✅ Get all notifications

### ⌨️ chrome.commands Tests
- ✅ Keyboard shortcut registration
- ✅ Command event handlers
- ✅ Multiple shortcuts
- ✅ `_execute_action` special command
- ✅ Get all commands
- ✅ Shortcut descriptions

## Keyboard Shortcuts

- **Ctrl+Shift+Y** - Trigger test command (shows notification)
- **Ctrl+Shift+N** - Show advanced notification with buttons
- **Ctrl+Shift+U** - Execute action (click toolbar icon)

## Installation

1. Open Nook browser
2. Navigate to extension management
3. Load this directory as an unpacked extension
4. Look for the extension icon in the toolbar

## Testing Instructions

### Manual Testing

1. **Action Test**
   - Click the toolbar icon
   - Verify popup opens
   - Check badge shows "4" in red
   - Click "Update Badge" button
   - Verify badge updates

2. **Context Menu Test**
   - Right-click anywhere on a page
   - Look for "Tier 1 API Tests" menu
   - Try each submenu item
   - Select text and right-click for selection menu

3. **Notification Test**
   - Click "Show Basic" in popup
   - Verify notification appears
   - Click "Show with Buttons"
   - Click notification buttons
   - Click "Clear All"
   - Verify all notifications clear

4. **Commands Test**
   - Press **Ctrl+Shift+Y**
   - Verify notification appears and badge turns green
   - Press **Ctrl+Shift+N**
   - Verify advanced notification appears
   - Press **Ctrl+Shift+U**
   - Verify popup opens
   - Click "List All Shortcuts" in popup
   - Verify all shortcuts are listed

### Background Console Testing

Open the background page console to see detailed logs:
- Action events
- Context menu events
- Notification events
- Command events
- API initialization

Expected console output:
```
🚀 Tier 1 APIs Test Extension - Background script loaded
✅ [chrome.action] Badge text set to "4"
✅ [chrome.action] Badge color set to red
✅ [chrome.action] Title updated
✅ [chrome.contextMenus] Parent menu created
✅ [chrome.contextMenus] Notification submenu created
✅ [chrome.contextMenus] Command submenu created
✅ [chrome.contextMenus] Selection menu created
✅ [chrome.commands] Registered commands: [...]
🎉 All Tier 1 API tests initialized!
```

## Integration Points

This extension demonstrates:
- Background service worker with all APIs
- Popup with interactive controls
- Event listeners across all APIs
- API coordination (e.g., commands triggering notifications)
- Badge updates from keyboard shortcuts
- Context menus triggering notifications
- Cross-API communication

## Expected Results

### On Extension Load
1. Badge shows "4" in red
2. Title set to "Tier 1 APIs Test - Ready!"
3. Context menus registered
4. Keyboard shortcuts active
5. Welcome notification appears after 1 second

### On Toolbar Click
1. Popup opens
2. All buttons functional
3. Status updates shown

### On Keyboard Shortcut
1. **Ctrl+Shift+Y**: Notification + green badge
2. **Ctrl+Shift+N**: Advanced notification with buttons
3. **Ctrl+Shift+U**: Popup opens

### On Context Menu
1. Parent menu visible
2. Submenus work
3. Notifications shown for menu actions

## Troubleshooting

### No keyboard shortcuts working
- Check if commands are registered: Click "List All Shortcuts" in popup
- Verify manifest.json has commands section
- Check background console for errors

### No context menus appearing
- Right-click on a web page (not extension popup)
- Check background console for menu creation logs
- Verify contextMenus permission in manifest

### Notifications not showing
- Check macOS notification settings
- Verify notifications permission in manifest
- Check background console for notification logs

### Badge not updating
- Verify action API is loaded
- Check popup console for badge update logs
- Try clicking "Update Badge" in popup

## File Structure

```
04-tier1-apis-test/
├── manifest.json       # Extension configuration with all permissions
├── background.js       # Background service worker with all API tests
├── popup.html         # Interactive popup UI
├── popup.js           # Popup logic and event handlers
├── icon16.png         # 16x16 icon
├── icon48.png         # 48x48 icon
├── icon128.png        # 128x128 icon
└── README.md          # This file
```

## Development Notes

- Uses Manifest V3 format
- Service worker background page (not persistent)
- All APIs tested in a single extension
- Comprehensive event handling
- Visual feedback for all actions
- Console logging for debugging

## Success Criteria

This extension is working correctly when:
1. ✅ Badge shows "4" on load
2. ✅ Keyboard shortcuts trigger notifications
3. ✅ Context menus appear on right-click
4. ✅ All popup buttons work
5. ✅ Notifications appear and respond to clicks
6. ✅ Console shows all API initialization logs
7. ✅ Badge turns green when Ctrl+Shift+Y pressed
8. ✅ Welcome notification appears on load

## API Coverage

| API | Methods/Events Tested | Coverage |
|-----|----------------------|----------|
| chrome.action | setBadgeText, setBadgeBackgroundColor, setTitle, onClicked | 100% |
| chrome.contextMenus | create, update, onClicked | 100% |
| chrome.notifications | create, clear, getAll, onClicked, onButtonClicked, onClosed | 100% |
| chrome.commands | getAll, onCommand | 100% |

## Next Steps

After verifying this extension works:
1. Test each keyboard shortcut
2. Test all context menu items
3. Test all notification features
4. Test all popup buttons
5. Check console logs for errors
6. Verify badge updates work
7. Test button notifications

This extension provides a complete test suite for all Tier 1 APIs! 🚀

