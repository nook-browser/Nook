# Nook App Store Distribution Exception

Nook is licensed under GPL-3.0. See [LICENSE](./LICENSE).

## Additional permission under GNU GPL version 3 section 7

> As additional permission under section 7, you are allowed to distribute the
> software through an app store, even if that store has restrictive terms and
> conditions that are incompatible with the GPL, provided that the source is
> also available under the GPL with or without this permission through a
> channel without those restrictive terms and conditions.

The proviso is the point. Nook's complete corresponding source stays public at
<https://github.com/l984-451/Nook> under plain GPL-3.0, with no additional
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

## Who granted this

Every copyright holder of Nook's own code has granted this permission. The
maintainer keeps the records outside this repo.

### Third-party code

The exception covers Nook's own source. It does not reach code Nook links that
others license under GPL-3.0, because Nook cannot add permissions to work it
does not own.

As of commit `d98dd76`, 2026-09-17, **Nook links no GPL-3.0 code it does not
own.** AdGuard's SafariConverterLib and the `@adguard/safari-extension` bundle
inside `nook-advanced-blocking.js` were both removed and replaced by
`adblock-rust` under MPL-2.0. See
[the iOS port design](./docs/superpowers/specs/2026-09-17-ios-port-design.md)
and [the parity record](./docs/superpowers/plans/2026-09-17-adblock-rust-parity.md).

Scriptlet bodies are the reason Nook executes none. Every general-purpose
scriptlet library is GPL-3.0: uBlock Origin's, `@adguard/scriptlets`, Adblock
Plus's snippets, and the uBO bodies embedded in `@ghostery/adblocker`. Brave's
`adblock-resources` is MPL-2.0 but holds only 17 Brave-specific scripts, and
Brave's real library comes from a uBlock Origin submodule. None of it is
grantable by Nook, so `injected_script` stays empty.

The filter lists under `Nook/Managers/ContentBlockerManager/Resources/` are
data rather than linked code, and travel as separate works under their own
terms.

### Not legal advice

This file was drafted by the maintainer with AI assistance. The wording follows
an established form used by other GPL projects for the same purpose. Have a
lawyer read it before the first App Store submission.
