# Nook Ad Blocker Architecture

## Overview

Nook blocks ads itself. There is no extension, no Safari content-blocker app, and no
AdGuard code in the build any more: SafariConverterLib and the `@adguard/safari-extension`
runtime were both removed in September 2026, along with `RequestStatsEngine` and its
blocked-request counter.

Rules are converted by Brave's adblock-rust, network blocking is handed to WebKit as
compiled `WKContentRuleList`s, and everything WebKit cannot express is done by Nook's own
scripts, injected into `WKWebView` as `WKUserScript`s.

The code is `Packages/NookBlocker/Sources/NookBlocker/`, Foundation and WebKit only, with
no AppKit, so it ports to iOS unchanged. It reaches the app through two protocols in
`BlockablePage.swift`: `BlockablePage` (one live page: `itemID`, `isOAuthFlow`, `webView`)
and `ContentBlockerHost` (the live pages, the shared `WKUserContentController`, and a hook
run against each freshly made controller). `PageSession` in `Packages/NookWeb` is the only
implementation today. Filter list snapshots and scripts are read through `Bundle.module`
from `Sources/NookBlocker/Resources/`.

## Pipeline

```
Filter lists (bundled snapshots in Resources/, refreshed on each list's own interval)
  ↓ FilterListManager
  ↓ RustContentBlockingConverter.convert()   (adblock-rust, feature `content_blocking`)
  ├─ content-blocking JSON → ContentRuleListCompiler → 30K-entry chunks
  │    → WKContentRuleListStore.compile() → [WKContentRuleList]
  │      (network blocking plus css-display-none, including :has())
  ├─ cosmetic rules the converter could not express → BlockerEngine (adblock::Engine)
  └─ raw $removeparam lines → TrackingParamStripper
```

**FilterListManager** downloads, caches and validates the lists. Defaults are always on and
ship as snapshots in `Resources/` (EasyList, EasyPrivacy, Peter Lowe's, the uBlock filters,
unbreak, badware, privacy and quick-fixes lists, URLhaus, AdGuard URL tracking, and the
bundle-only `nook-filters-default.txt`), so the first run is protected before any network
request. Each list refreshes on its own `! Expires:` interval with a conditional GET.
`scripts/refresh-filter-lists.sh` updates the bundled snapshots and runs in CI before each
release build.

**ContentRuleListCompiler** splits the converted rules into 30,000-entry chunks and compiles
each into the `WKContentRuleListStore`. Results are keyed by a SHA-256 of the rule text, and
a `converter-adblock-rust` stamp file in the cache directory invalidates anything written by
the old converter.

**BlockerEngine** owns the single `adblock::Engine` in the app. It is `@MainActor` with a
synchronous `configuration(for:topUrl:)` lookup, because the main-frame config script has to
be installed before the navigation commits; only `build(rules:)` runs off the actor. Plain
cosmetic filters never reach it, since the converter turns those into `css-display-none`
entries WebKit applies itself. Scriptlets are not executed (the engine is given no
resources), and true procedural operators (`:has-text`, `:upward`, `:matches-css`) are
skipped.

**AdvancedRulesEngine** installs the scripts and answers lookups. `nook-cosmetic.js` runs at
document start in all frames: in the main frame it reads `window.__nookCosmeticConfig`, set
synchronously by the config script before navigation; in subframes it asks the
`nookAdvancedBlocking` reply handler. Either way it injects one stylesheet. Alongside it go
the static site scripts (`facebook-sponsored-blocker.js`,
`instagram-sponsored-blocker.js`, `twitter-ad-blocker.js`, plus `facebook-feed-prune.js` and
`instagram-feed-prune.js`, which strip Meta's ads out of the feed data before the page
renders them) and `nook-stealth-redirects.js`, which answers a blocked ad URL with the resource uBlock
Origin's `$redirect=` rules name for it, so the request does not read as a failure to
anti-adblock scripts and an ad library that a page depends on gets a working shim. Its
table is built per navigation by `AdvancedRulesEngine` and carried in the same config
script as the cosmetic rules, because most `$redirect=` rules are domain-scoped.
`$redirect-rule=` is excluded: it applies only to requests that are blocked anyway, which
the page cannot know.

**TrackingParamStripper** implements `$removeparam` for main-frame navigations. It parses
the raw filter lines the converter drops, and `PageSession` applies it in
`decidePolicyFor` before the load starts.

## Exemptions

`ContentBlockerManager` owns enable and disable, the allowlist (domain suffix match), the
per-tab temporary disable, the OAuth exemption from `OAuthDetector`, the per-navigation
main-frame config, and the subframe lookups behind the `nookAdvancedBlocking` handler. An
exempt web view has its rule lists and scripts removed; state changes on transitions, not on
every navigation.

## Script ownership

Every script the blocker injects starts with `// Nook Content Blocker`, or
`// Nook Content Blocker Config` for the per-navigation main-frame config. There is no
remove-one API, so changing one script means `removeAllUserScripts()` and re-adding the
survivors. That controller is shared with `WKWebExtensionController`, which is never told
its content scripts were cleared, so filter with `.nookOwned`
(`WKUserScript+NookOwned.swift`) before re-adding and let the extension
controller look after its own. Prefer install-once, self-gating scripts: put changing state
behind the message handler instead of baking it into the script source.

## Rules

- **Never convert a rule that cancels another rule.** A cosmetic exception (`#@#`) and
  `$badfilter` both describe the absence of a rule and have no standalone content-blocking
  form. The crate inverts an `UNHIDE` filter's domains into `unless_domain`, so
  `redtube.com#@#svg` becomes "hide every svg on the web except redtube.com".
  `cancels_another_rule` in `Nook/ThirdParty/AdblockRustFFI/src/content_blocking_ffi.rs`
  skips both, and `tests/no_overbroad_rules.rs` fails the build if one escapes.
- **An `@@` exception cannot override a block in another list.** WebKit evaluates each
  compiled `WKContentRuleList` on its own. Use a scriptlet or the stub table instead.
- **Never stub a vendor that validates its payload.** Ad-Shield compares the script it
  fetches against an `X-Length` header, and a `data:` URL has no headers, so an empty stub
  reads as malformed and it replaces the document with an error modal. Blocking is the
  milder failure. Stubs only suit detectors that check whether a load succeeded.
- Do not re-inject scripts after load; scriptlets are not idempotent.
- Do not rewrite `:has()` rules out of the content rule list; WebKit supports them natively.
- Site scripts observe `childList` only, validate content (for instance the word
  "Sponsored"), set `display: none`, and guard with `window.__nook<Name>Loaded`.

## Known limits

No `$redirect`, `$csp`, `$replace` or `$header`, since WebKit's rule lists cannot express
them. No scriptlet execution. Procedural cosmetic operators are dropped. Nothing counts
blocked requests any more.

## Updating dependencies

- Filter list snapshots: `scripts/refresh-filter-lists.sh` (keep its URL list in sync with
  `FilterListManager`'s defaults).
- adblock-rust: `Nook/ThirdParty/AdblockRustFFI/build.sh` (needs Rust). It produces
  `NookAdblock.xcframework`, consumed by `Packages/NookBlocker` as a `binaryTarget`. The
  `content-blocking` and `css-validation` features are both required: without the latter the
  crate's selector validator is a stub that never classifies procedural filters, so they
  arrive as raw text and inject invalid CSS.
