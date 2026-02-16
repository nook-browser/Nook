<div align="center">
  <img width="230" height="230" src="/assets/icon.png" alt="Nook Logo">
  <h1><b>Nook</b></h1>
  <p>
    A fast, minimal browser with a sidebar-first design for macOS.
    <br>
  </p>
</div>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-15.5+-blue" alt="macOS 15.5+"></a>
  <a href="https://swift.org/"><img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0-green" alt="GPL-3.0"></a>
  <a href="https://github.com/nook-browser/Nook/pulls"><img src="https://img.shields.io/github/issues-pr/nook-browser/Nook" alt="Open pull requests"></a>
  <a href="https://github.com/nook-browser/Nook/issues"><img src="https://img.shields.io/github/issues/nook-browser/Nook" alt="Open issues"></a>
  <a href="https://github.com/nook-browser/Nook/graphs/contributors"><img src="https://img.shields.io/github/contributors/nook-browser/Nook" alt="Contributors"></a>
  <a href="https://deepwiki.com/nook-browser/Nook"><img src="https://deepwiki.com/badge.svg" alt="DeepWiki"></a>
  <a href=""><img src="https://img.shields.io/coderabbit/prs/github/nook-browser/Nook?utm_source=oss&utm_medium=github&utm_campaign=nook-browser%2FNook&labelColor=171717&color=FF570A&link=https%3A%2F%2Fcoderabbit.ai&label=CodeRabbit+Reviews" alt="CodeRabbit Pull Request Reviews"></a>
</p>


<p align="center">
  <a href="https://github.com/nook-browser/nook/releases/download/v1.0.2/Nook-v1.0.2.dmg"><img src="https://img.shields.io/badge/Download%20for-macOS-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS"></a>
</p>

> **Looking for the dev branch?** [Click here](https://github.com/nook-browser/Nook/tree/dev)

## Features  

-  **Sidebar-first navigation** – vertical tabs that feel natural and uncluttered.
-  **Performance** – optimized with modern macOS APIs for speed and low memory use.  
-  **Minimal, modern UI** – focused on content, not chrome.  

<p align="center">
  <img src="https://github.com/user-attachments/assets/dbfe9e9c-82f5-4f59-a073-b86ea05e5f26" alt="Nook screenshot">
</p>


## Getting Started  

### Download
[![Download for macOS](https://img.shields.io/badge/Download%20for-macOS-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/nook-browser/nook/releases/download/v1.0.2/Nook-v1.0.2.dmg)

### or, Build from Source

#### Prerequisites  
- macOS 15.5+
- [Xcode](https://developer.apple.com/xcode/) (to build from source)
```bash

git clone https://github.com/nook-browser/Nook.git
cd Nook
open Nook.xcodeproj
```

Some obj-c libraries may not play nice with Intel Macs, though there should technically be full interoperability. You can use any number of resources to debug. You will also need to delete a couple lines of code for *older* versions of macOS than Tahoe (26.0).

You’ll need to set your personal Development Team in Signing to build locally.

Join our Discord to help with development: https://discord.gg/J3XfPvg7Fs

## Project Structure

```
Nook/
├── Nook/
│   ├── Managers/              # Core business logic and state management
│   │   ├── BrowserManager/    # Central coordinator for browser state
│   │   ├── TabManager/        # Tab lifecycle and organization
│   │   ├── ProfileManager/    # User profile and data isolation
│   │   ├── ExtensionManager/  # Browser extension support
│   │   ├── HistoryManager/    # Browsing history tracking
│   │   ├── DownloadManager/   # File download handling
│   │   ├── CookieManager/     # Cookie storage and management
│   │   ├── CacheManager/      # Web cache management
│   │   ├── SettingsManager/   # User preferences
│   │   ├── DialogManager/     # System dialogs and alerts
│   │   ├── SearchManager/     # Search functionality
│   │   ├── SplitViewManager/  # Split-screen tab viewing
│   │   ├── PeekManager/       # Quick preview feature
│   │   ├── DragManager/       # Drag-and-drop operations
│   │   └── ...
│   │
│   ├── Models/                # Data models and business entities
│   │   ├── Tab/              # Tab model and state
│   │   ├── Space/            # Workspace organization
│   │   ├── Profile/          # User profile data model
│   │   ├── History/          # Browsing history entries
│   │   ├── Extension/        # Extension metadata
│   │   ├── Settings/         # Settings data structures
│   │   └── BrowserConfig/    # Browser configuration
│   │
│   ├── Components/            # SwiftUI views and UI components
│   │   ├── Browser/          # Main browser window UI
│   │   ├── Sidebar/          # Sidebar navigation UI
│   │   ├── CommandPalette/   # Quick action interface
│   │   ├── Settings/         # Settings screens
│   │   ├── Extensions/       # Extension management UI
│   │   ├── Peek/             # Preview overlay UI
│   │   ├── Dialog/           # Modal dialogs
│   │   ├── FindBar/          # In-page search
│   │   └── ...
│   │
│   ├── Utils/                # Utility functions and helpers
│   │   ├── WebKit/           # WebKit extensions
│   │   ├── Shaders/          # Metal shaders for UI effects
│   │   └── Debug/            # Development tools
│   │
│   ├── Protocols/            # Swift protocols and interfaces
│   ├── Adapters/             # External API adapters
│   ├── ThirdParty/           # Third-party dependencies
│   └── Supporting Files/     # App configuration and resources
│
├── Config/                   # Build and project configuration
└── assets/                   # Static assets and resources
```

### Architecture Overview

Nook follows a manager-based architecture where:
- **Managers** handle business logic and coordinate between different parts of the app
- **Models** represent data and state using Swift's `@Observable` macro
- **Components** are SwiftUI views that reactively update based on model changes
- **BrowserManager** acts as the central coordinator, connecting all managers together


### LICENSES
With the exception of third-party libraries in Nook/ThirdParty, all code is under the GPL 3.0 License. The relevant third-party code is licensed per-folder under a variety of free, open-source software licenses.

