# Nook App Store Distribution Exception

Nook is licensed under GPL-3.0. See [LICENSE](./LICENSE).

## Additional permission under GNU GPL version 3 section 7

> As additional permission under section 7, you are allowed to distribute the
> software through an app store, even if that store has restrictive terms and
> conditions that are incompatible with the GPL, provided that the source is
> also available under the GPL with or without this permission through a
> channel without those restrictive terms and conditions.

The proviso is the point. Nook's complete corresponding source stays public at
<https://github.com/nook-browser/Nook> under plain GPL-3.0, with no additional
terms and no acceptance required. Anyone who receives Nook through Apple's App
Store can obtain that source from a channel Apple does not govern.

This is an additional permission within the meaning of GPL-3.0 section 7. You
may remove it from any copy of Nook you convey, and removing it leaves your
rights under GPL-3.0 unchanged.

This permission covers distribution only. It grants no rights in the Nook name,
wordmark, or icon. See [TRADEMARK.md](./TRADEMARK.md).

## Source file notice

Section 7 requires that added terms appear in the relevant source files, either
in full or as a pointer. Nook uses a pointer. Files carrying the exception
begin with:

```
// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
```

### Third-party code

The exception covers Nook's own source. It does not reach code Nook links that
others license under GPL-3.0, because Nook cannot add permissions to work it
does not own.

**The macOS build links GPL-3.0 code Nook does not own, and therefore cannot be
conveyed through any app store.** It is distributed as a notarized DMG through
Sparkle, a channel with no terms that conflict with the GPL, so the exception is
not needed for it and does not apply to it. The macOS build is not sandboxed and
so was never eligible for the Mac App Store in any case.

The code in question is uBlock Origin's scriptlet library, vendored verbatim at
commit `e530864c464e912840e72b60e9f072bc54daba5e` under
[`Packages/NookBlocker/ThirdParty/ubo-scriptlets/`](./Packages/NookBlocker/ThirdParty/ubo-scriptlets/).
Copyright (C) 2019-present Raymond Hill, GNU GPL version 3 or later. Each file
keeps its original header and none is modified;
[`scripts/build-scriptlets.mjs`](./scripts/build-scriptlets.mjs) reads them and
generates the resource manifest the blocker hands to adblock-rust. Every
general-purpose scriptlet library is GPL-3.0, uBlock Origin's included, and
`@adguard/scriptlets`, Adblock Plus's snippets and the uBO bodies embedded in
`@ghostery/adblocker` are no different. Brave's `adblock-resources` is MPL-2.0
but holds only 17 Brave-specific scripts and no general library at all.

**The iOS build excludes them**, because the App Store is its only channel and
the exception cannot be extended to Raymond Hill's work. The exclusion is a
single `#if os(iOS)` in
[`ScriptletResources.swift`](./Packages/NookBlocker/Sources/NookBlocker/ScriptletResources.swift),
which is a licence boundary rather than a feature flag. Nothing else may be
allowed to switch it, and an iOS build that ships these bodies is a licence
violation rather than a bug.

AdGuard's SafariConverterLib and the `@adguard/safari-extension` bundle inside
`nook-advanced-blocking.js` were removed in September 2026 and replaced by
`adblock-rust` under MPL-2.0. That replacement stands on its own merits and is
unaffected by the above.

The filter lists under `Packages/NookBlocker/Sources/NookBlocker/Resources/` are
data rather than linked code, and travel as separate works under their own
terms.

### Not legal advice

This file was drafted by the maintainer with AI assistance. The wording follows
an established form used by other GPL projects for the same purpose. Have a
lawyer read it before the first App Store submission.
