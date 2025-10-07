# Nook
*A fast, minimal browser with a sidebar-first design.*

[![Download for macOS](https://img.shields.io/badge/Download%20for-macOS-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/nook-browser/nook/releases/download/v1.0.2/Nook-v1.0.2.dmg)

![Image from Imgflip](https://github.com/user-attachments/assets/dbfe9e9c-82f5-4f59-a073-b86ea05e5f26)

[![Stars](https://img.shields.io/github/stars/nook-browser/Nook?style=social)](https://github.com/nook-browser/Nook/stargazers)
[![Forks](https://img.shields.io/github/forks/nook-browser/Nook?style=social)](https://github.com/nook-browser/Nook/network/members)
[![Pull Requests](https://img.shields.io/github/issues-pr/nook-browser/Nook)](https://github.com/nook-browser/Nook/pulls)
[![Issues](https://img.shields.io/github/issues/nook-browser/Nook)](https://github.com/nook-browser/Nook/issues)
[![Contributors](https://img.shields.io/github/contributors/nook-browser/Nook)](https://github.com/nook-browser/Nook/graphs/contributors)
[![License](https://img.shields.io/github/license/nook-browser/Nook)](./LICENSE)

---

## Features  

-  **Sidebar-first navigation** – vertical tabs that feel natural and uncluttered.
-  **Performance** – optimized with modern macOS APIs for speed and low memory use.  
-  **Minimal, modern UI** – focused on content, not chrome.  


## Getting Started  
[![Download for macOS](https://img.shields.io/badge/Download%20for-macOS-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/nook-browser/nook/releases/download/v1.0.1/Nook-v1.0.1.dmg)

### Build from Source

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
