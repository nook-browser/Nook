# Nook Ad Blocker Architecture

## Overview

Nook's ad blocker is built directly into the browser on top of the same two AdGuard
components AdGuard for Safari and wBlock use, both GPL-3.0:

- **SafariConverterLib** (SPM, product `ContentBlockerConverter`, targets `ContentBlockerConverter` + `FilterEngine`)
  converts AdGuard/uBlock filter rules into Safari content-blocker JSON plus an "advanced rules" text,
  and provides `FilterEngine`/`WebExtension` for per-URL lookup of those advanced rules.
- **@adguard/safari-extension** (npm, bundled as `Resources/nook-advanced-blocking.js`) applies advanced
  rules in-page. It bundles AdGuard ExtendedCss and AdGuard Scriptlets. Rebuild recipe:
  `Resources/BUILD-advanced-blocking.md`.

Unlike a Safari extension, Nook injects directly into `WKWebView` via `WKUserScript`, which gives
per-tab control (whitelist, temporary disable, OAuth exemption) and no extension process.

Everything in `Nook/Managers/ContentBlockerManager/` is Foundation + WebKit only, so it is reusable
as-is for an iOS target.

## Pipeline

```
Filter lists (bundled snapshots in Resources/, refreshed daily from the network)
  ↓ FilterListManager.loadAllFilterRulesAsLines()        (disk cache → bundled fallback)
  ↓ SafariConverterLib.convertArray(advancedBlocking: true)
  ├─ safariRulesJSON  → ContentRuleListCompiler → 30K-entry chunks → WKContentRuleListStore.compile()
  │                     → [WKContentRuleList]   (network blocking, css-display-none incl. :has())
  └─ advancedRulesText → AdvancedRulesEngine.build() → WebExtension.buildFilterEngine()
                         (trie index, serialized under Application Support/.../AdvancedRules)
```

Compiled rule lists and the advanced text are cached by SHA-256 of the input rules, so a launch with
unchanged lists does no conversion.

## Three blocking layers

1. **WKContentRuleList** (native, out of process): network blocking, exceptions, simple and `:has()`
   element hiding, plus a few hardcoded YouTube endpoint rules. Added to the shared
   `WKWebViewConfiguration` and to every fresh `WKUserContentController`.
2. **Advanced rules** (cosmetic CSS with styles, extended CSS, scriptlets, JS): looked up per frame URL
   by `AdvancedRulesEngine.configuration(for:topUrl:)` and applied by the runtime script.
   - Main frame: `Tab.decidePolicyFor` → `ContentBlockerManager.setupContentBlockerScripts` embeds the
     configuration as `window.__nookAdvancedBlockingConfig` in a user script that precedes the runtime,
     so rules apply synchronously at document start.
   - Subframes: the runtime posts `{url, topUrl}` to the `nookAdvancedBlocking` reply handler
     (`WKScriptMessageHandlerWithReply`, registered on every controller) and applies the answer.
     AdGuard's delayed-event dispatcher holds `DOMContentLoaded`/`load` up to 1s meanwhile.
   Domain, path, `$elemhide`/`$generichide` and scriptlet exceptions are handled by FilterEngine.
3. **Site-specific scripts** (`Resources/*-blocker.js`): YouTube, Facebook, X. Added once as static
   user scripts, main frame only, wrapped in a hostname guard. Each guards against double execution
   with `window.__nook<Name>Loaded`.

## Script ownership

Every user script the blocker owns starts with `// Nook Content Blocker` (static runtime + site
scripts) or `// Nook Content Blocker Config` (per-navigation main-frame configuration). Removal and
replacement filter by those prefixes; nothing else in the app may use them.

Static scripts live on the shared configuration's controller and are copied into each new controller
by `BrowserConfiguration.freshUserContentController()`. Per navigation only the config script changes.

## Exemptions

`isExempt(tab, host)` = blocker disabled, tab temporarily disabled (basic-auth flow), host or any
parent domain whitelisted, or OAuth flow. Exempt webviews have rule lists and scripts removed and are
tracked in a weak set; state only changes on transitions, not on every navigation.

## Filter lists

Default (always on, snapshots bundled): EasyList, EasyPrivacy, Peter Lowe's, uBlock filters /
unbreak / badware / privacy / quick fixes, URLhaus. `nook-filters-default.txt` is bundle-only.
Optional lists (AdGuard, Fanboy, regional) are downloaded on enable. Updates use conditional GET
(ETag / If-Modified-Since) once every 24h; the first update runs right after activation.

## Known limits (WebKit)

No `$redirect`, `$csp`, `$removeparam`, `$replace`, `$header`; no request counters. Scriptlets run in
the page world from the user-script realm, so they are not blocked by page CSP.

## Updating dependencies

- Runtime JS: follow `Resources/BUILD-advanced-blocking.md` (bump `@adguard/safari-extension`).
- SafariConverterLib: bump the SPM requirement in the Xcode project; keep it on the same major as the
  npm package.
- Filter list snapshots: re-download the files in `Resources/` (same names as `FilterListManager.defaultLists`).

## History

- Originally 97 hand-written scriptlet templates with a custom parser.
- March 2026: SafariConverterLib + AdGuard Scriptlets corelibs JSON, with a home-grown advanced-rules
  interpreter (`AdvancedBlockingEngine`).
- September 2026: interpreter replaced by SafariConverterLib's FilterEngine + `@adguard/safari-extension`;
  per-frame lookup, proper extended CSS, exception handling, no double injection, bundled list snapshots.
