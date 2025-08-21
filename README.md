# Nook (Pulse)

Please review your code and use Xcode’s formatter (Shift + Cmd + I) before creating a PR. Make sure you are pulling from the `dev` branch.

You’ll need to set your personal Development Team in Signing to build locally.

Join our Discord to help with development: https://discord.gg/J3XfPvg7Fs

## WebExtensions (WKWebExtension)

Pulse integrates native WebKit WebExtensions via `WKWebExtension`, `WKWebExtensionContext`, and `WKWebExtensionController`. This enables standard WebExtensions (MV2/MV3) to run without custom JS shims.

- Requirements: macOS 15.5+ (Sequoia), Xcode 16.4+.
- Architecture: A single shared `WKWebViewConfiguration` is used for all browsing views. `ExtensionManager` configures the `webExtensionController` on this shared config and exposes the current window/tabs via lightweight adapters.
- Permissions: Requested/optional permissions and host match patterns are surfaced in a native permission prompt. Decisions are applied with `setPermissionStatus`.
- Content scripts: Inject automatically based on the extension manifest; the app avoids injecting page JS for extension behaviors.

### Install an extension

1. Build and run Pulse on macOS 15.5+.
2. Menu: `Extensions > Install Extension...` then choose a folder with `manifest.json` or a `.zip` package.
3. Review and grant permissions when prompted.
4. Manage enable/disable/uninstall under `Settings > Extensions`.

Notes
- Extensions are copied to `~/Library/Application Support/Pulse/Extensions/<id>/`.
- When an extension provides a browser action (popup), its icon appears near the URL bar; clicking it opens the native popup.
- Chrome-specific behavior is not emulated; compatibility follows WebKit’s WebExtensions implementation: https://github.com/w3c/webextensions
