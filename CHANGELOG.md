# Changelog

## 1.1.1

### Added

- Ask Nook, the AI chat in the sidebar, can run on Apple Intelligence on your Mac with no API key. It becomes the default when no other provider is set up. It answers questions about the page
- Links you open from a tab now nest under it, and new tabs open right below the tab you're on
- Back, forward and reload moved up beside the window buttons
- Liquid Glass throughout the sidebar, History and Downloads, Peek and Ask Nook
- PDF controls to zoom, print, save or open the file in Preview. Cmd+P prints any page, and a page's own print button works now
- Settings > Appearance > Hide border lets the page sit flush against the window (#370)

### Changed

- Peek opens on its own only for links from favorites and pinned tabs to another site. Option-click still peeks any link. On a regular tab, a link that would open a new window opens a new tab
- Peek is a little smaller, with close, split and new tab in one glass group on its left
- Peek and the sign-in window run like a normal tab now, with the full ad blocker, site tweaks, downloads and page dialogs
- Sidebar PiP only picks up a playing landscape video with sound, which keeps Shorts, reels and feed autoplay out. The player's title and progress bars no longer show in the sidebar
- The sidebar has a minimum width so back, forward and reload always fit
- Ask Nook shows its reply as it's written

### Fixed

- Videos on YouTube, Facebook and Instagram flashed black for single frames
- The top of a web page dragged the window, and text there couldn't be selected
- The window buttons now hide with the sidebar and stay hidden after leaving full screen
- Peek could draw the page cut off at the top and left
- Email, phone and other app links did nothing. They open in their app now
- The Settings button in Ask Nook and every Space Settings shortcut and menu item did nothing
- Gemini 3 failed after its first tool call, and GPT-5 and o-series models failed through the OpenAI-compatible provider
- Save Image could send the site's cookies along to wherever the image redirected
- In History, the time filter never refreshed and deleting a row lost your place. History older than 100 days is now cleared in every space; before, only the space Nook opened in was cleared
- In Downloads, Move to Trash opened Finder, and the download indicator could show the wrong download

## 1.1.0

Nook is being revived!

The bundle identifier has changed, so the updater in 1.0.x cannot install the latest version. Download the DMG and replace Nook in Applications to launch it.

The latest release requires macOS 26.

- Reworked and improved tab management
- Spaces and Profiles are simplified and combined now
- Enhanced the built-in adblocking system
- Added custom tweaks for YouTube and Social Media sites
- Improved split view
- PiP is more Arc-like (WIP, tested mainly on YouTube)
- Passkeys work through password managers. iCloud Keychain passkeys are still unavailable for now
- Performed multiple passes to harden security
