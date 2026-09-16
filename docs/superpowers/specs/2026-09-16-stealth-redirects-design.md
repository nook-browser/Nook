# Stealth redirects: make blocked requests look like empty successes

Status: design, not implemented
Date: 2026-09-16

## Problem

WebKit's content rule lists can only block a request. A blocked request fails
loudly: `fetch` rejects, `XMLHttpRequest` reports status 0, `<script>` and
`<img>` fire `error`. Anti-adblock services read exactly those signals.

Three sites hit in one session, all detecting Nook through failed loads:

- **vsco.co** (Freestar wall): loads `gpt.js` and a test image, shows a modal
  with a scroll lock when they fail.
- **jeep-cj.com**: `fetch` and `XHR` for `adsbygoogle.js`; either failure shows
  a modal that a MutationObserver rebuilds when hidden.
- **Ad-Shield** sites generally: a failed loader script is treated as proof and
  triggers the ad-recovery path.

uBlock Origin answers this with `$redirect=noopjs`: the request "succeeds" and
returns an inert stub, so nothing fails and there is nothing to detect. Safari
content blockers have no redirect action, so today Nook writes per-site
scriptlets after the fact, one site at a time, each one a fresh investigation.

The filter lists Nook already ships carry the redirect rules: 167 in
`ublock-filters.txt`, 45 in `ublock-privacy.txt`. The targets are dominated by
a handful of stubs (`noopjs` 172, `google-ima.js` 105, `noopmp3-0.1s` 36,
`noop.js` 34, `1x1.gif` 27, `nooptext` 17, `fingerprint2.js` 16). Nook parses
these rules today only for `$removeparam`; the redirect part is dropped.

## What we ship

A page-world script, injected at document start, that answers a small set of
known ad URLs from a local stub table instead of letting them fail. No ad code
runs and no ad renders: the stub is inert. The page simply cannot tell the
difference between "blocked" and "loaded something useless".

Two parts:

1. **A stub table**, built at filter-compile time from the `$redirect` rules in
   the lists, as `[{pattern, stub}]`, injected per navigation as JSON.
2. **The shim**, which intercepts the four ways a page starts a request and
   serves the stub when a URL matches.

### Why the decision is local

Nook could ask native "would this be blocked?" per request through
`WKScriptMessageHandlerWithReply`, the way `nookAdvancedBlocking` does for
subframe lookups. Do not. It puts an IPC round trip in front of every
subresource, against priority 1, and it cannot work at all for the cases that
need a synchronous answer (an `<img>` src assignment). The table is small, the
match is a regex test in-page, and no request pays for IPC.

### What the shim intercepts

| Entry point | Action |
|---|---|
| `fetch(url)` | Resolve with a `Response` carrying the stub body, status 200 |
| `XMLHttpRequest` | Report `readyState` 4, `status` 200, stub `responseText` |
| `HTMLScriptElement.src` / `setAttribute` | Rewrite to a `data:` URL holding the stub before the load starts |
| `HTMLImageElement.src` / `setAttribute` | Rewrite to a 1x1 transparent GIF `data:` URL |

Rewriting `src` before the load means the browser itself fires `load`, so event
ordering, `document.currentScript` and timing all stay honest. Nothing is
patched after the fact and no synthetic events are dispatched.

### Stubs

Phase 1 carries only the inert ones, which cover the detection cases:

- `noopjs` / `noop.js`: empty script
- `1x1.gif` / `2x2.png`: transparent pixel
- `nooptext` / `noop.txt`: empty body

`google-ima.js`, `googletagservices_gpt.js` and `fingerprint2.js` are API
shims, not empty files: a page calls into them and breaks if the object is
missing. They are worth adopting from uBlock Origin's resource set later, per
stub, each with a site that proves it. uBO is GPL-3.0 and so is Nook, so reuse
is fine with attribution.

## Where it plugs in

- Build the table in `ContentRuleListCompiler` alongside the existing
  `$removeparam` parse, keyed by the same rules hash so it is cached, not
  recomputed per navigation.
- Inject like `AdvancedRulesEngine` injects its config: a document-start user
  script in `PageSession`, all frames, source starting with
  `// Nook Content Blocker` so the existing removal filter finds it.
- Honour every existing escape hatch: host allowlist, per-tab temporary
  disable, OAuth exemption. If blocking is off for the page, do not inject.
- `Resources/nook-stealth-redirects.js`, Foundation and WebKit only, no AppKit,
  so it ports to iOS with the rest of the blocker.

## Bait elements, the other half

The same detectors plant an element with class names like
`pub_300x250 text-ad textAd adBanner ad_box` and check whether it is hidden.
Our generic cosmetic rules hide it, which is a pure tell: the element is 1x1 and
off-screen, so hiding it protects nobody.

Two options, in order of preference:

1. **Drop the generic (no-domain) cosmetic rules for the classic bait names**
   during compilation. Real ad containers are hidden by network blocking and by
   domain-scoped rules anyway. One change, every site, no per-site rules.
2. Keep writing per-site `#@#` exceptions, as jeep-cj.com has now. Works,
   scales badly.

Option 1 needs a check on a handful of ad-heavy sites for layout gaps before it
ships. It is independent of the shim; either can land first.

## Non-goals

- **No local proxy.** Synthesising HTTPS responses means terminating TLS with
  our own root certificate: a large security surface and a constant latency and
  battery cost against priority 1.
- **No User-Agent spoofing.** jeep-cj.com only runs its XHR probe because our
  UA says Safari, but changing it breaks more than it fixes.
- **No per-request native round trip.** See above.
- **No paywall or registration-wall bypass.** This is about ads and trackers.

## Risks

- **Sites that depend on a failed ad request.** Some code paths fall back when
  an ad script fails and hang when it "succeeds" but does nothing. This is the
  real risk, and it is why the table stays small and the feature needs a
  settings toggle plus the existing per-site disable.
- **Half-working stubs.** An empty `gpt.js` is worse than a blocked one for a
  page that calls into it. Hence inert stubs only in phase 1.
- **Maintenance.** The stub table follows the lists, so it refreshes with them.
  Hand-written entries do not, and should stay rare.

## Phases

1. Shim plus inert stubs, table hand-seeded with the top patterns
   (`adsbygoogle.js`, `gpt.js`, `pubads`, Ad-Shield loaders). Settings toggle,
   default on. Verify against the three sites above.
2. Parse `$redirect` from the lists at compile time and drop the hand-seeded
   table.
3. Adopt uBO's API shims one at a time, each with a site that needs it.
4. Bait-element change, measured on ad-heavy sites for layout damage.

## Verification

No test target, so this is manual, driven through the MCP server:

- vsco.co, jeep-cj.com and one Ad-Shield site: no wall, no scroll lock, no ads,
  with the blocker on.
- Each site with blocking off for the host: unchanged from today.
- A page with real ad slots (any news site): slots stay empty, layout intact.
- `console` clean of new errors; blocked-request counts unchanged, since the
  content rule list still blocks everything the shim does not answer.
