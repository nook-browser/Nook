<div align="center">
  <img width="230" height="230" src="/assets/icon.png" alt="Sociopath Logo">
  <h1><b>Sociopath</b></h1>
  <p>
    The most minimal, NON-AI browser for macOS, built exclusively with WebKit for Apple Silicon.
    <br>
    Designed for consultants, designers, coders, knowledge-workers, and high-performers who need to get shit done.
    <br>
    No accounts required, no AI features, just uncompromising performance focused on your goals.
    <br>
    Data stays in the EU.
  </p>
</div>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://badgen.net/badge/macOS/15.5+/blue" alt="macOS 15.5+"></a>
  <a href="https://swift.org/"><img src="https://badgen.net/badge/Swift/6/orange" alt="Swift"></a>
  <a href="./LICENSE"><img src="https://badgen.net/badge/License/GPL-3.0/green" alt="GPL-3.0"></a>
    <a href="https://github.com/WeMake-Labs/sociopath/pulls"><img src="https://img.shields.io/github/issues-pr/WeMake-Labs/sociopath" alt="Open pull requests"></a>
  <a href="https://github.com/WeMake-Labs/sociopath/issues"><img src="https://img.shields.io/github/issues/WeMake-Labs/sociopath" alt="Open issues"></a>
  <a href="https://github.com/WeMake-Labs/sociopath/graphs/contributors"><img src="https://img.shields.io/github/contributors/WeMake-Labs/sociopath" alt="Contributors"></a>
</p>

<p align="center">
  <a href="https://github.com/WeMake-Labs/sociopath/releases"><img src="https://img.shields.io/badge/Download%20for-macOS-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS"></a>
</p>

## Features

- **Sidebar-first navigation** – vertical tabs that feel natural and uncluttered.
- **Performance** – optimized with modern macOS APIs for speed and low memory use.
- **Minimal, modern UI** – focused on content, not chrome.
- **NON-AI browser** – built exclusively with WebKit for Apple Silicon, no AI features or tracking.
- **Privacy-focused** – no accounts required, data stays in the EU.

<p align="center">
  <img src="https://github.com/user-attachments/assets/dbfe9e9c-82f5-4f59-a073-b86ea05e5f26" alt="screenshot">
</p>

## Getting Started

### Download

[![Download for macOS](https://img.shields.io/badge/Download%20for-macOS-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/WeMake-Labs/sociopath/releases)

Sociopath is a focused fork of [Nook](https://browsewithnook.com/) by the Nook team, reoriented toward a minimal, NON-AI macOS browser. Original repository: [github.com/nook-browser/Nook](https://github.com/nook-browser/Nook).

### or, Build from Source

#### Prerequisites

- macOS 15.5+ (Apple Silicon recommended)
- [Xcode](https://developer.apple.com/xcode/) (to build from source)

```sh
git clone https://github.com/WeMake-Labs/sociopath.git
cd sociopath
open Nook.xcodeproj
```

Some obj-c libraries may not play nice with Intel Macs, though there should technically be full interoperability. You can use any number of resources to debug. For older versions of macOS than Tahoe (26.0), you may need to delete a couple lines of code. Sociopath is optimized for Apple Silicon and requires macOS 15.5+.

You’ll need to set your personal Development Team in Signing to build locally.

### LICENSES

With the exception of third-party libraries in Sociopath/ThirdParty, all code is under the GPL 3.0 License. The relevant third-party code is licensed per-folder under a variety of free, open-source software licenses.

Sociopath is developed as a side project by [WeMake-Labs](https://wemake.cx) in Germany, maintaining the same open-source licensing as the original Nook project.
