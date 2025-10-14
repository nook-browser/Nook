# Nook Browser - Codebase Documentation

## Repository Structure

This is a **single-purpose repository** containing the Nook browser application - a fast, minimal browser with a sidebar-first design for macOS.

### Architecture Overview

Nook follows the **MVVM pattern** with SwiftUI, using:
- **SwiftUI** for the UI layer
- **Observation** pattern for state management
- **Manager classes** for business logic
- **SwiftData** for persistence

## Key Components

### Core Managers

#### BrowserManager (`Nook/Managers/BrowserManager/`)
- Central coordinator for all browser operations
- Manages windows, tabs, spaces, and profiles
- Handles navigation, history, and downloads
- Integrates with all other managers

#### TabManager (`Nook/Managers/TabManager/`)
- Manages tab lifecycle and state
- Handles tab persistence and restoration
- Manages spaces (tab groups)
- Handles tab unloading for memory management

#### ProfileManager (`Nook/Managers/ProfileManager/`)
- Manages user profiles with isolated data stores
- Handles profile creation, switching, and deletion
- Manages profile-specific settings and data

#### SettingsManager (`Nook/Managers/SettingsManager/`)
- Centralized settings management
- Persists user preferences to UserDefaults
- Manages app-wide configuration
- **Contains**: KeyboardShortcutManager instance

#### KeyboardShortcutManager (`Nook/Managers/KeyboardShortcutManager/`)
- **NEW**: Centralized keyboard shortcut management system
- Replaces hardcoded shortcuts throughout the app
- Provides customizable shortcuts with persistence
- Integrates with BrowserManager for action execution

### UI Components

#### Settings System (`Nook/Components/Settings/`)
- Native macOS settings window with tabbed interface
- Includes:
  - General settings (appearance, search engine)
  - Privacy settings (cookies, cache)
  - Profiles management
  - **NEW**: Keyboard shortcuts customization
  - Extensions (experimental)
  - Advanced settings

#### ShortcutRecorderView (`Nook/Components/Settings/ShortcutRecorderView.swift`)
- Custom SwiftUI component for recording keyboard shortcuts
- Provides real-time conflict detection
- Visual feedback during recording
- Integration with KeyboardShortcutManager

### Data Models

#### KeyboardShortcut (`Nook/Models/KeyboardShortcut/`)
- **NEW**: Data model for keyboard shortcuts
- Defines shortcut actions, key combinations, and metadata
- Includes default shortcuts for all browser operations
- Supports customizable and non-customizable shortcuts

## Keyboard Shortcuts System

### Architecture

The keyboard shortcuts system follows a centralized architecture:

1. **KeyboardShortcutManager**: Central coordinator that:
   - Maintains the registry of all shortcuts
   - Handles global key event monitoring
   - Persists custom shortcuts to UserDefaults
   - Executes actions through BrowserManager

2. **ShortcutAction enum**: Defines all available shortcut actions:
   - Navigation (back, forward, refresh)
   - Tab management (new, close, switch)
   - Window management (new window, close browser)
   - Tools (command palette, dev tools)

3. **ShortcutsSettingsView**: Settings interface for:
   - Viewing all shortcuts by category
   - Recording new key combinations
   - Enabling/disabling shortcuts
   - Resetting to defaults

### Integration Points

- **NookApp.swift:32**: Initializes KeyboardShortcutManager and connects it to BrowserManager
- **BrowserManager**: Executes all shortcut actions through executeAction() method
- **SettingsManager.swift:13**: Hosts KeyboardShortcutManager as a property
- **UserDefaults**: Persists custom shortcuts under "keyboard.shortcuts" key

### Migration from Hardcoded Shortcuts

Previously, shortcuts were defined in multiple places:
- NookCommands struct in NookApp.swift (lines 261-509)
- Hardcoded key listeners throughout the app

Now, all shortcuts are centralized:
- Default shortcuts defined in KeyboardShortcut.defaultShortcuts (lines 207-251)
- Custom shortcuts persisted to UserDefaults
- Global event monitoring in KeyboardShortcutManager.setupGlobalMonitor() (lines 251-270)
- Conflict detection and validation in hasConflict() method (lines 125-132)

### Key Features

1. **Customizable**: Users can change most shortcuts through settings
2. **Persistent**: Custom shortcuts survive app restarts
3. **Conflict Detection**: Prevents duplicate key combinations
4. **Version-aware**: Automatically merges new shortcuts on updates (version 3)
5. **Category Organization**: Shortcuts grouped by function (Navigation, Tabs, etc.)

## Persistence

### SwiftData
- Primary persistence for browser data (tabs, history, bookmarks)
- Managed through Persistence.shared.container

### UserDefaults
- User preferences and settings
- **NEW**: Custom keyboard shortcuts
- App configuration and flags

### Tab Persistence
- Atomic snapshot system for reliable tab restoration
- Handles app termination gracefully
- Stores tab state, navigation history, and space assignments

## Testing

Test files are located in respective test targets:
- Unit tests for managers and models
- UI tests for critical user flows
- Integration tests for keyboard shortcuts

## Build Configuration

- **Main target**: Nook browser application
- **Debug builds**: Include additional debugging options
- **Release builds**: Optimized for performance
- Minimum macOS version: 15.5+

## Third-Party Dependencies

Located in `Nook/ThirdParty/`:
- **MuteableWKWebView**: Web view muting control
- **HTSymbolHook**: Symbol hooking for advanced features
- **BigUIPaging**: UI paging components
- **SwiftSoup**: HTML parsing
- **FaviconFinder**: Favicon detection and retrieval

## Development Guidelines

1. **Manager Pattern**: Business logic belongs in manager classes
2. **Observation**: Use @Observable for state management
3. **Persistence**: All user data must be persisted
4. **Keyboard Shortcuts**: Add new actions to ShortcutAction enum
5. **Settings**: New settings go through SettingsManager
