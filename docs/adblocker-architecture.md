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
Optional lists (AdGuard, Fanboy, regional) are downloaded on enable. Each list is refreshed on its
own `! Expires:` interval (uBO quick fixes: 8h, URLhaus: 12h, EasyList: 4 days; default 24h, clamped
1h to 7d) with conditional GET (ETag / If-Modified-Since). A check for due lists runs right after
activation and hourly. `scripts/refresh-filter-lists.sh` re-downloads the bundled snapshots; CI runs
it before every release build.

## Tracking parameter removal (`$removeparam`)

WebKit cannot rewrite URLs, and SafariConverterLib drops `$removeparam` rules. `TrackingParamStripper`
parses them from the raw filter lines (uBO privacy list, AdGuard URL Tracking Protection, unbreak) and
`Tab.decidePolicyFor` restarts main-frame GET navigations without the matching parameters. Exempt tabs
and back/forward navigations are left alone. Matching is host-suffix plus substring, not full ABP
pattern semantics.

## Blocked-request counts

Content rule lists report nothing, so the same rules are also loaded into Brave's adblock-rust
(`Nook/ThirdParty/AdblockRustFFI`, MPL-2.0, C API over a static library). `nook-request-stats.js`
observes every resource URL a page tries to load (fetch, XHR, beacon, WebSocket, and DOM-inserted
img/script/link/iframe/media via one MutationObserver), batches them, and posts to the
`nookRequestStats` handler. `RequestStatsEngine` checks them on a serial queue and adds to
`Tab.blockedRequestCount`, which resets on each main-frame navigation and shows in the extension
library's Content Blocker row. The engine is serialized per rules hash so warm starts deserialize
instead of rebuilding. Counting never blocks or delays a request.

## Known limits (WebKit)

No `$redirect`, `$csp`, `$replace`, `$header`. Scriptlets run in the page world from the user-script
realm, so they are not blocked by page CSP; raw `#%#` JS rules still go through a script element and
lose on strict-CSP sites. Counts are approximate: adblock-rust and the Safari conversion can disagree
on edge cases, and CSS background images are not observed.

## Updating dependencies

- Runtime JS: follow `Resources/BUILD-advanced-blocking.md` (bump `@adguard/safari-extension`).
- SafariConverterLib: bump the SPM requirement in the Xcode project; keep it on the same major as the
  npm package.
- Filter list snapshots: `scripts/refresh-filter-lists.sh` (keep its URL list in sync with `FilterListManager.defaultLists`).
- adblock-rust: `Nook/ThirdParty/AdblockRustFFI/build.sh` (needs Rust; the built `.a` is committed).

## History

- Originally 97 hand-written scriptlet templates with a custom parser.
- March 2026: SafariConverterLib + AdGuard Scriptlets corelibs JSON, with a home-grown advanced-rules
  interpreter (`AdvancedBlockingEngine`).
- September 2026: interpreter replaced by SafariConverterLib's FilterEngine + `@adguard/safari-extension`;
  per-frame lookup, proper extended CSS, exception handling, no double injection, bundled list snapshots.
