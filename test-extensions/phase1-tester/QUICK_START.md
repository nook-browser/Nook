# Phase 1 Tester - Quick Start Guide

## 🚀 5-Minute Test

### 1. Install (30 seconds)
```
1. Open Nook → Extensions
2. Enable Developer Mode
3. Load Unpacked → Select this folder
4. Done!
```

### 2. Test Task 1.1 - Ports (1 minute)
```
Open popup → Connect Port → Send Message → Disconnect
✅ Should see: "Active" status, messages exchanged
```

### 3. Test Task 1.2 - Messaging (2 minutes)
```
Click all 4 buttons: Ping, Get Data, Storage Test, Round Trip
✅ Should see: Real data in responses (NOT just {success: true})
❌ If warning appears: Task 1.2 not fully working
```

### 4. Test Task 1.3 - Commands (1 minute)
```
Press: Cmd+Shift+1, Cmd+Shift+2, Cmd+Shift+3
✅ Should see: Commands appear in history
```

### 5. Test Task 1.3 - Menus (30 seconds)
```
Right-click on any page → Click test menu item
✅ Should see: Menu click in history
```

## ✅ Pass Criteria

All status badges should be **GREEN (Pass)**

If **RED (Fail)** → Check console logs for errors

## 📊 Expected Results

### Task 1.2 - Critical Check
**Good (Pass):**
```json
{
  "type": "pong",
  "receivedAt": 1234567890,
  "messageCount": 1,
  "originalMessage": {...}
}
```

**Bad (Fail):**
```json
{
  "success": true
}
```
⚠️ This synthetic response means Task 1.2 needs work!

## 🐛 Quick Debug

**Nothing working?**
- Check console for errors
- Verify background service worker started
- Look for: "🚀 Phase 1 Tester - Background Service Worker Started"

**Ports fail?**
- Task 1.1 implementation needed
- Check ExtensionManager port storage

**Messaging fails?**
- Task 1.2 implementation needed
- Check response tracking system

**Commands/Menus fail?**
- Task 1.3 implementation needed
- Check event delivery to background

## 📋 Full Documentation

See `README.md` for complete testing guide
See `TEST_REPORT_TEMPLATE.md` for detailed report

