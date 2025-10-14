# Smart Shortcut Testing Guide

## Debug Features Added

I've added extensive debug logging to help identify why toasts might not be showing:

### Log Categories
- 🎹 Keyboard shortcut detection
- 🌐 Web app shortcut identification
- 📄 Google Docs/Sites detection
- 🍞 Toast display and state changes
- ⏰ Timer events and double-press windows
- ✅ Successful actions and confirmations

## Testing Steps

### 1. Enable Debug Logging
Look for these log messages in Console.app or Xcode console:
- Filter for "SmartShortcutManager" or "Nook"

### 2. Test Google Docs Detection
1. Navigate to docs.google.com or sheets.google.com
2. Press ⌘R (refresh), ⌘T (new tab), or ⌘W (close tab)
3. Expected behavior:
   - First press: Google Docs handles it, toast appears
   - Second press within 15 seconds: Nook action executes

### 3. Test General Web Apps
1. Navigate to any web app with keyboard shortcuts (Figma, Draw.io, etc.)
2. Press common shortcuts like ⌘S, ⌘R, etc.
3. Toast should appear for web app shortcuts

### 4. Debug Checklist
If toasts aren't showing, check for these log messages:

```
🎹 Smart shortcut manager handling: [Action] ([Shortcut])
🌐 Potential web app shortcut detected: [Action] (Google Docs: true/false)
⏰ Starting web app detection for [Action]
🍞 Showing toast for [Action]
🍞 Toast state: show=true, message='[Message]', shortcut='[Shortcut]'
```

### 5. Manual Test (for development)
You can add this test code to manually trigger toasts:

```swift
// In any view with @EnvironmentObject smartShortcutManager:
Button("Test Toast") {
    smartShortcutManager.showToast = true
    smartShortcutManager.toastMessage = "Press ⌘S again to save"
    smartShortcutManager.toastShortcut = "⌘S"
}
```

## Common Issues & Fixes

### Issue: Toasts not appearing
- Check that SmartShortcutManager is properly injected as environment object
- Verify @Observable macro is working correctly
- Ensure WebsiteView has the environment object

### Issue: Double-press not working
- Verify lastPressedShortcut state is maintained
- Check timing logic (15-second window)
- Ensure timer cleanup is working

### Issue: Google Docs not detected
- Verify current URL detection is working
- Check browserManager.currentTabForActiveWindow()?.url
- Ensure URL matching logic is correct

## Expected Log Output for Working System

```
🎹 Smart shortcut manager handling: Refresh (⌘R)
📄 Google Docs/Sheets detected: true
🌐 Potential web app shortcut detected: Refresh (Google Docs: true)
⏰ Starting web app detection for Refresh
🍞 Showing toast for Refresh
🍞 Toast state: show=true, message='Press ⌘R again to refresh', shortcut='⌘R'
[User presses ⌘R again]
✅ Double press detected for Refresh, executing Nook action
🍞 Hiding toast
```

## Next Steps

If logs show the system is working but toasts still don't appear:
1. Check SwiftUI view update cycles
2. Verify environment object propagation
3. Test with different content views
4. Check for view hierarchy issues