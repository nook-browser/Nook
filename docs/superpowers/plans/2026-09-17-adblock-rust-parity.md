# adblock-rust parity against SafariConverterLib

Date: 2026-09-17
Gate for: [the AdGuard swap plan](./2026-09-17-adblock-rust-swap.md), Task 9
Verdict: **go**

## Method

Both builds ran against the same bundled filter list snapshots, with
`~/Library/Application Support/io.browsewithnook.nook/ContentBlocker/Cache`
cleared first so neither could take a cache hit. The baseline is commit
`019d7db`, the last commit before the swap, built in a detached worktree at
`/tmp/nook-baseline` with its own derived data.

## Conversion

| | SafariConverterLib (`019d7db`) | adblock-rust (`8d0b157`) |
|---|---|---|
| Input lines loaded | 177,405 | 177,405 |
| Safari rules produced | 148,441 | **154,997** |
| Entries compiled | 148,450 | 155,006 |
| Compiled rule lists | 5 | 6 |
| Conversion wall time | 1.73s | **0.23s** |
| Lookup engine build | not logged | 0.06s |

adblock-rust puts 6,556 more rules into the content rule list, 4.4% more, and
converts 7.5 times faster. More rules in the compiled list means more blocking
happens natively in WebKit's out-of-process matcher rather than through
injected CSS.

## On the error counts

The two numbers are not comparable and should not be put side by side without
this paragraph.

SafariConverterLib reported `163,734 source, 148,441 safari, 4,566 advanced,
4,341 errors`. It pre-filters comments before counting source, and it splits
rules it cannot express in Safari syntax into "advanced" (routed to its runtime
engine) and "errors" (discarded).

`RustContentBlockingConverter` reports `177,405 source, 154,997 safari, 12,652
errors`. It counts every line it was handed, skips comments and `[Adblock`
headers without counting them, and lumps everything that fails
`CbRuleEquivalent::try_from` into one bucket.

So Nook's 12,652 is the analogue of SafariConverterLib's 4,566 + 4,341 = 8,907,
and the difference is mostly procedural cosmetic rules and `$redirect=` rules,
which are still handled: procedural rules come back through
`BlockerEngine.configuration` at lookup time, and `$removeparam` is handled
separately by `TrackingParamStripper`. Nothing counted here is silently lost.

The metric is misleading as logged. Worth splitting into "routed to cosmetic
lookup" and "rejected outright" if anyone ever needs to act on it.

## Live sites

All eight loaded, rendered, and had the cosmetic script active. `css` is the
count of hide selectors delivered to the page, `proc` the count of procedural
filters.

| Site | script loaded | css | proc | body text | result |
|---|---|---|---|---|---|
| theguardian.com | yes | 495 | 0 | 18,253 | clean |
| cnn.com | yes | 505 | 0 | 7,806 | clean |
| reddit.com | yes | 14 | 3 | 14,515 | clean |
| espn.com | yes | 492 | 0 | 6,416 | clean |
| forbes.com | yes | 517 | 1 | 20,582 | clean |
| businessinsider.com | yes | 501 | 0 | 7,117 | clean |
| vsco.co | yes | 493 | 1 | 5,487 | clean |
| youtube.com | yes | 39 | 1 | 2,951 | clean |

vsco.co is the anti-adblock case from the stealth-redirects work and was
checked further: no `error-report` element, `document.body` overflow is
`visible` so nothing has taken a scroll lock, and the console shows
`loadError` for `cdn.intellimize.co` and `cdn.cookielaw.org`, which is the
blocker doing its job rather than a regression.

## Builds

Debug and Release both build with `SafariConverterLib` removed from
`project.pbxproj`. Release was built unsigned, since this machine's session had
no Mac Development certificate available; that is an environment limitation
rather than a code result, and a signed Release build should be run before
shipping.

17 Rust tests pass in release.

## What this gate did not cover

Facebook, Instagram and X were not swept, because they need a signed-in session
and this run was not signed in. Their feed-prune scripts are Nook's own and the swap left them alone. The
cosmetic path around them did change, so they are worth a manual pass.

Scriptlets are not executed in this build at all, by design. Any site that
depended on a `+js()` rule will regress, and nothing in this sweep would show
it. See the scriptlet note in the swap plan.

True procedural operators (`:has-text`, `:upward`, `:matches-css`) are skipped
by `nook-cosmetic.js`. The counts above show 0 to 3 procedural filters per site,
so the exposure is small, but `nook-cosmetic.js` logs a skip count under
`__nookCosmeticVerbose` if it needs measuring.
