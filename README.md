<div align="center">
  <img width="270" height="270" src="/assets/icon.png" alt="Nook Logo">
  <h1><b>Nook</b></h1>
  <p>
    A fast, minimal browser with a sidebar-first design for macOS.
    <br>
  </p>
</div>

<p align="center">
  <a href="https://www.apple.com/macos/"><img src="https://badgen.net/badge/macOS/15.5+/blue" alt="macOS 15.5+"></a>
  <a href="https://swift.org/"><img src="https://badgen.net/badge/Swift/6/orange" alt="Swift"></a>
  <a href="./LICENSE"><img src="https://badgen.net/badge/License/GPL-3.0/green" alt="GPL-3.0"></a>
    <a href="https://github.com/nook-browser/Nook/pulls"><img src="https://img.shields.io/github/issues-pr/nook-browser/Nook" alt="Open pull requests"></a>
  <a href="https://github.com/nook-browser/Nook/issues"><img src="https://img.shields.io/github/issues/nook-browser/Nook" alt="Open issues"></a>
  <a href="https://github.com/nook-browser/Nook/graphs/contributors"><img src="https://img.shields.io/github/contributors/nook-browser/Nook" alt="Contributors"></a>
</p>

<p align="center">
  <img src="https://github.com/user-attachments/assets/dbfe9e9c-82f5-4f59-a073-b86ea05e5f26" alt="Nook screenshot">
</p>

<p align="center">
  <a href="https://github.com/nook-browser/nook/releases/download/v1.0.2/Nook-v1.0.2.dmg"><img src="https://img.shields.io/badge/Download%20for-macOS-000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS"></a>
</p>


<p align="center">
  <a href="https://github.com/nook-browser/Nook/stargazers"><img src="https://img.shields.io/github/stars/nook-browser/Nook?style=social" alt="GitHub stars"></a>
  <a href="https://github.com/nook-browser/Nook/network/members"><img src="https://img.shields.io/github/forks/nook-browser/Nook?style=social" alt="GitHub forks"></a>
</p>

---

## Features  

-  **Sidebar-first navigation** – vertical tabs that feel natural and uncluttered.
-  **Performance** – optimized with modern macOS APIs for speed and low memory use.  
-  **Minimal, modern UI** – focused on content, not chrome.  


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



### LICENSES
With the exception of third-party libraries in Nook/ThirdParty, all code is under the GPL 3.0 License. The relevant third-party code is licensed per-folder under a variety of free, open-source software licenses.

