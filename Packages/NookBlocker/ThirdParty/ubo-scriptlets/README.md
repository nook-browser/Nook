# uBlock Origin scriptlet resources

Verbatim copies from [gorhill/uBlock](https://github.com/gorhill/uBlock), pinned at
commit `e530864c464e912840e72b60e9f072bc54daba5e`, under the upstream directory layout so the relative imports resolve
unchanged. Refresh with `scripts/refresh-ubo-scriptlets.sh`.

**Copyright (C) 2019-present Raymond Hill. Licensed under GNU GPL version 3 or later.**
Each file keeps its original header. Nothing here is modified; `scripts/build-scriptlets.mjs`
reads these files and generates the resource manifest Nook hands to adblock-rust.

Two directories are vendored. `src/js/resources/` holds the scriptlets proper.
`src/web_accessible_resources/` holds uBO's redirect resources, of which the
`data: 'text'` entries listed in `src/js/redirect-resources.js` double as
argument-less scriptlets (`##+js(noeval)` and the like). The binary ones are
left out: they exist for `$redirect`, which WebKit's content rule lists cannot
do.

Because this is GPL-3.0 code Nook does not own, Nook's App Store exception cannot
reach it. See [LICENSE-EXCEPTION.md](../../../../LICENSE-EXCEPTION.md): the macOS
build links these and is distributed only as a notarized DMG; the iOS build excludes
them entirely.
