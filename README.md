<div align="center">
  <img width="230" height="230" src="/assets/icon.png" alt="Nook Logo">
  <h1><b>Nook</b></h1>
  <p>
    A fast, minimal browser with a sidebar-first design for macOS.
  </p>
</div>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://img.shields.io/badge/macOS-26.0+-blue" alt="macOS 26.0+"></a>
  <a href="https://swift.org/"><img src="https://img.shields.io/badge/Swift-5-orange" alt="Swift"></a>
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-GPL--3.0-green" alt="GPL-3.0"></a>
</p>

<p align="center">
  <a href="https://github.com/nook-browser/Nook/releases/latest"><img src="https://img.shields.io/badge/Download%20for-macOS-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS"></a>
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/dbfe9e9c-82f5-4f59-a073-b86ea05e5f26" alt="Nook screenshot">
</p>

---

## Status

Nook started as a fork of [nook-browser/Nook](https://github.com/nook-browser/Nook), which went dormant in March 2026. As of September 2026 I've taken it over as a solo project: the upstream remote is gone, nothing merges back, and this repo is the only source of truth going forward.

## Why this exists

A few things I actually care about, in order:

- **Speed**: startup, tab switching, scrolling, sidebar interaction. If a change makes the browser feel slower, it doesn't ship.
- **Ad blocking that's actually built in**: not an extension you have to remember to install. Filter list compiling and rule matching happen in-process.
- **Battery and CPU balance**: no polling timers, no busy-waiting. Heavy work, like filter compiling and on-device AI, runs off the main thread, is cancellable, and unloads when idle.

Everything else is negotiable against those three.

## Features

- **Sidebar-first navigation**: spaces, pinned tabs, and folders instead of a horizontal tab strip.
- **Built-in ad and tracker blocking**: content rule lists plus AdGuard-style scriptlets, compiled and cached locally.
- **Web extensions**: Chrome Web Store-compatible extensions via WKWebExtension.
- **On-device AI**: local LLM tab grouping on Apple Silicon (MLX), plus an AI chat sidebar that talks to your own provider (Gemini, OpenRouter, Ollama, or any OpenAI-compatible endpoint).
- **YouTube tweaks and built-in SponsorBlock**: hide Shorts and home shelves, auto-skip sponsor segments.
- **Split view, command palette, quick peek**: the usual power-user shortcuts, without a settings maze.
- **Profile isolation**: separate, non-persistent data stores for incognito and ephemeral profiles.

## Requirements

- macOS 26.0 or later, Apple Silicon
- Xcode 26 or later to build (Xcode 27 also works; the deployment target stays 26.0)

## Building

```bash
git clone https://github.com/nook-browser/Nook.git
cd Nook
open Nook.xcodeproj
```

You'll need to set your own Development Team under Signing & Capabilities to build and run locally. To build unsigned from the command line instead:

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Repository layout

```
Nook/
├── App/                 App entry point, AppDelegate, window management
├── Nook/Managers/       ~30 feature managers (business logic, one per domain)
├── Nook/Models/         Data models and SwiftData entities
├── Nook/Components/     SwiftUI views, including Settings
├── Nook/Design/         Design tokens (spacing, radii, motion, elevation)
├── Settings/            NookSettingsService, backed by UserDefaults
├── CommandPalette/      Command palette UI
└── docs/                Architecture notes and design specs
```

Nook uses a manager-based architecture: each feature domain (tabs, extensions, ad blocking, downloads, and so on) has its own `@MainActor`-confined manager, coordinated through `BrowserManager`. `CLAUDE.md` has the full breakdown if you're digging in.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and PR guidelines. AI-assisted contributions are fine as long as you disclose them and can actually explain what the code does.

## License

Nook is licensed under [GPL-3.0](./LICENSE). With the exception of the third-party libraries in `Nook/ThirdParty`, all code here is GPL-3.0; the third-party code is licensed per-folder under its own terms.
