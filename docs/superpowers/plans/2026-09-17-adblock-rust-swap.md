# AdGuard to adblock-rust Swap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove AdGuard's GPL-3.0 SafariConverterLib and `@adguard/safari-extension` from Nook, replacing both with `adblock-rust` under MPL-2.0, so that Nook links no GPL code it does not own.

**Architecture:** `adblock-rust` already ships in `Nook/ThirdParty/AdblockRustFFI` and is used for one job, request counting. Two of its modules cover both AdGuard jobs: `content_blocking` converts filter syntax to WKContentRuleList JSON, and `cosmetic_filter_cache` answers per-URL cosmetic lookups. Three new C functions expose them. `ContentRuleListCompiler` keeps its chunking, SHA-256 cache, and store management, swapping only the converter call. `AdvancedRulesEngine` keeps its public shape so `ContentBlockerManager` and `PageSession` do not change, swapping `WebExtension`/`FilterEngine` for the new FFI. `nook-advanced-blocking.js` is replaced by a Nook-owned script.

**Tech Stack:** Rust (`adblock` 0.13.3, MPL-2.0, `staticlib` crate type, C ABI), Swift 5 with `@MainActor` confinement, WebKit (`WKContentRuleListStore`, `WKUserScript`), plain ES5-compatible JavaScript in a WKUserScript.

**Spec:** [docs/superpowers/specs/2026-09-17-ios-port-design.md](../specs/2026-09-17-ios-port-design.md), phase 1.

**Status:** Tasks 1 to 3 are done (`6cae0d5`, `dd27696`, `d5d272a`). Reading the
crate during execution overturned three assumptions this plan was written on,
and the tasks below were corrected to match what was built. See
"Corrections made during execution" near the end.

## Global Constraints

- Deployment target is macOS 26.0. Never add `@available` or `#available` guards below 26.
- Swift language mode 5. Strict concurrency is not enabled.
- Apple Silicon only. Release builds use `-arch arm64`.
- There is no test target in the Xcode project. `xcodebuild test -scheme Nook` fails. Swift-side verification is a build plus a manual run. Rust-side verification is `cargo test`.
- `Packages/NookTabsCore` and the Rust crate are the only places automated tests can run today. Put testable logic there.
- Every blocker-owned user script must begin with `// Nook Content Blocker` or `// Nook Content Blocker Config`. Removal filters on those exact prefixes.
- Do not re-inject scripts after load. Scriptlets are not idempotent.
- Do not rewrite `:has()` rules out of the content rule list. WebKit supports them natively.
- `WKWebView.configuration` returns a copy. Mutating it silently does nothing. `userContentController` is the exception and is shared.
- `WKUserContentController.userScripts` is a lazily bridged proxy. Evaluate everything you need from it before calling `removeAllUserScripts()`. Touching the old array afterwards traps in Release builds only.
- An `@@` exception in one compiled `WKContentRuleList` cannot override a block in another. WebKit evaluates each list independently.
- The crate's `Engine` and `CosmeticFilterCache` are `Send` but not `Sync`. One actor or queue owns each instance.
- Logging uses `Logger(subsystem:category:)` with privacy annotations. `.debug` never reaches `log show`; use `.info` or `.notice` for anything you intend to read back.
- Commit messages disclose AI assistance per `CONTRIBUTING.md`, using the trailer `Assisted by Claude Code.`
- The working tree may hold another session's uncommitted edits. Before each commit, run `git status --porcelain` and stage only the paths this plan names.

## File Structure

**Rust, `Nook/ThirdParty/AdblockRustFFI/`:**
- `Cargo.toml`: modify, enable the `content-blocking` feature.
- `src/lib.rs`: modify, add the conversion function and keep it thin.
- `src/content_blocking_ffi.rs`: create, conversion FFI plus its tests.
- `src/cosmetic_ffi.rs`: create, cosmetic cache FFI plus its tests.
- `include/nook_adblock.h`: modify, declare the new functions.
- `build.sh`: unchanged in this plan. iOS slices belong to phase 3.

**Swift, `Nook/Managers/ContentBlockerManager/`:**
- `RustContentBlockingConverter.swift`: create, Swift wrapper over the conversion FFI.
- `CosmeticFilterEngine.swift`: create, Swift wrapper over the cosmetic FFI.
- `ContentRuleListCompiler.swift`: modify, swap the converter.
- `AdvancedRulesEngine.swift`: modify, swap the lookup engine, keep the public shape.
- `Resources/nook-cosmetic.js`: create, replaces `nook-advanced-blocking.js`.
- `Resources/nook-advanced-blocking.js`: delete.
- `Resources/BUILD-advanced-blocking.md`: delete.

**Project:**
- `Nook.xcodeproj/project.pbxproj`: modify, remove the `ContentBlockerConverter` package dependency.

Each Rust FFI module is its own file because each owns a distinct opaque pointer type with distinct lifetime rules, and `lib.rs` is already the place someone looks for the request-matching API that exists today.

---

### Task 1: Enable the content-blocking feature and prove the crate module is reachable

**Files:**
- Modify: `Nook/ThirdParty/AdblockRustFFI/Cargo.toml`
- Modify: `Nook/ThirdParty/AdblockRustFFI/src/lib.rs`

**Interfaces:**
- Consumes: nothing.
- Produces: the `adblock::content_blocking` module becomes importable by later tasks. No public FFI yet.

**Context:** `content_blocking` sits behind a Cargo feature that is off by default. The current `Cargo.toml` line is `adblock = "0.13.3"`. Without this task, every later task fails to compile with an error about a missing module rather than a missing feature.

- [ ] **Step 1: Write the failing test**

Append to `Nook/ThirdParty/AdblockRustFFI/src/lib.rs`, inside the existing `mod tests` block:

```rust
    #[test]
    fn content_blocking_module_is_available() {
        use adblock::content_blocking::{CbRuleEquivalent, CbType};
        use adblock::lists::{ParseOptions, ParsedFilter};
        use std::convert::TryFrom;

        let parsed = adblock::lists::parse_filter("||example.com^", true, ParseOptions::default())
            .expect("filter should parse");
        let ParsedFilter::Network(network) = parsed else {
            panic!("expected a network filter");
        };
        let equivalent = CbRuleEquivalent::try_from(network).expect("should convert");
        let rules: Vec<_> = equivalent.into_iter().collect();
        assert_eq!(rules.len(), 1);
        assert!(matches!(rules[0].action.typ, CbType::Block));
        assert!(rules[0].trigger.url_filter.contains("example"));
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd Nook/ThirdParty/AdblockRustFFI && cargo test content_blocking_module_is_available
```

Expected: FAIL to compile, with an error naming `adblock::content_blocking` as an unresolved module.

- [ ] **Step 3: Enable the feature**

In `Nook/ThirdParty/AdblockRustFFI/Cargo.toml`, replace the dependency line:

```toml
[dependencies]
adblock = { version = "0.13.3", features = ["content-blocking"] }
```

Add `css-validation` as well. Its name undersells what it does: without it the
crate's `validate_css_selector` is a stub that wraps every selector as a plain
`CssSelector`, so `:has-text`, `:upward`, `:matches-css` and `:style` are never
classified as procedural. They then arrive in `hide_selectors` as raw text and
get injected as invalid CSS, and one invalid selector in a comma-joined rule
invalidates the whole rule, so a single such filter could disable cosmetic
hiding for a site. It also stops the converter emitting `css-display-none`
actions with selectors Safari cannot parse.

It costs 282KB in the static library. Worth it.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd Nook/ThirdParty/AdblockRustFFI && cargo test content_blocking_module_is_available
```

Expected: PASS. If the assertion on `rules.len()` fails rather than the compile, read what `CbRuleEquivalent` produced and adjust the assertion to match the crate's real output rather than forcing the crate to match the test. This test checks reachability and nothing more.

- [ ] **Step 5: Verify the whole existing suite still passes**

```bash
cd Nook/ThirdParty/AdblockRustFFI && cargo test --release
```

Expected: PASS, including `ffi_smoke`.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git status --porcelain
git add Nook/ThirdParty/AdblockRustFFI/Cargo.toml Nook/ThirdParty/AdblockRustFFI/Cargo.lock Nook/ThirdParty/AdblockRustFFI/src/lib.rs
git commit -m "build(adblock): enable the content-blocking crate feature

adblock::content_blocking sits behind a feature that is off by default, so
the module is invisible until it is named in Cargo.toml.

Assisted by Claude Code."
```

---

### Task 2: Conversion FFI

**Files:**
- Create: `Nook/ThirdParty/AdblockRustFFI/src/content_blocking_ffi.rs`
- Modify: `Nook/ThirdParty/AdblockRustFFI/src/lib.rs`
- Modify: `Nook/ThirdParty/AdblockRustFFI/include/nook_adblock.h`

**Interfaces:**
- Consumes: the `content-blocking` feature from Task 1.
- Produces:
  - `char *nook_adblock_convert_to_content_blocking(const char *rules_utf8, size_t rules_len, size_t *out_rule_count, size_t *out_error_count)`: returns a NUL-terminated UTF-8 JSON array of WKContentRuleList rule objects, or NULL on failure. Free with `nook_adblock_string_free`.
  - `void nook_adblock_string_free(char *s)`: frees a string returned by any `char *` function in this crate. NULL is a no-op.

**Context:** `ContentRuleListCompiler` chunks at 30,000 entries and converts the full rule set in one call today. Keep that shape: one call in, one JSON array out, and let the Swift side chunk as it already does. The rule and error counts exist so the Swift side can log the same comparison line it logs today for SafariConverterLib.

- [ ] **Step 1: Write the failing test**

Create `Nook/ThirdParty/AdblockRustFFI/src/content_blocking_ffi.rs`:

```rust
//! C ABI over adblock::content_blocking: filter text to WKContentRuleList JSON.

use crate::guard;
use adblock::content_blocking::{CbRule, CbRuleEquivalent};
use adblock::lists::{parse_filter, ParseOptions, ParsedFilter};
use std::convert::TryFrom;
use std::ffi::CString;
use std::os::raw::c_char;
use std::ptr;

/// Convert ABP/uBlock filter text into a JSON array of WKContentRuleList rules.
/// Writes the converted rule count to `*out_rule_count` and the count of lines
/// that failed to convert to `*out_error_count`; either may be NULL.
/// Returns NULL on a null/non-UTF-8 input. Free with nook_adblock_string_free.
#[no_mangle]
pub unsafe extern "C" fn nook_adblock_convert_to_content_blocking(
    rules_utf8: *const c_char,
    rules_len: usize,
    out_rule_count: *mut usize,
    out_error_count: *mut usize,
) -> *mut c_char {
    if rules_utf8.is_null() {
        return ptr::null_mut();
    }
    let bytes = std::slice::from_raw_parts(rules_utf8 as *const u8, rules_len);
    let Ok(text) = std::str::from_utf8(bytes) else {
        return ptr::null_mut();
    };
    guard(
        || {
            let (rules, errors) = convert_text(text);
            let Ok(json) = serde_json::to_string(&rules) else {
                return ptr::null_mut();
            };
            if !out_rule_count.is_null() {
                *out_rule_count = rules.len();
            }
            if !out_error_count.is_null() {
                *out_error_count = errors;
            }
            match CString::new(json) {
                Ok(c) => c.into_raw(),
                Err(_) => ptr::null_mut(),
            }
        },
        ptr::null_mut(),
    )
}

/// Free a string returned by this crate. NULL is a no-op.
#[no_mangle]
pub unsafe extern "C" fn nook_adblock_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// Returns the converted rules and the number of lines that could not convert.
fn convert_text(text: &str) -> (Vec<CbRule>, usize) {
    let opts = ParseOptions::default();
    let mut out: Vec<CbRule> = Vec::new();
    let mut errors = 0usize;

    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('!') || line.starts_with("[Adblock") {
            continue;
        }
        match parse_filter(line, true, opts) {
            Ok(ParsedFilter::Network(network)) => match CbRuleEquivalent::try_from(network) {
                Ok(equivalent) => out.extend(equivalent.into_iter()),
                Err(_) => errors += 1,
            },
            Ok(ParsedFilter::Cosmetic(cosmetic)) => match CbRule::try_from(cosmetic) {
                Ok(rule) => out.push(rule),
                Err(_) => errors += 1,
            },
            Err(_) => errors += 1,
        }
    }
    (out, errors)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    fn convert(text: &str) -> Vec<Value> {
        let (rules, _) = convert_text(text);
        serde_json::from_str(&serde_json::to_string(&rules).unwrap()).unwrap()
    }

    #[test]
    fn network_block_rule_converts() {
        let out = convert("||ads.example.com^");
        assert_eq!(out.len(), 1);
        assert_eq!(out[0]["action"]["type"], "block");
        assert!(out[0]["trigger"]["url-filter"].as_str().unwrap().contains("ads"));
    }

    #[test]
    fn exception_rule_becomes_ignore_previous_rules() {
        let out = convert("@@||example.com/ok.js");
        assert_eq!(out.len(), 1);
        assert_eq!(out[0]["action"]["type"], "ignore-previous-rules");
    }

    #[test]
    fn cosmetic_rule_becomes_css_display_none() {
        let out = convert("example.com##.sponsored");
        assert_eq!(out.len(), 1);
        assert_eq!(out[0]["action"]["type"], "css-display-none");
        assert_eq!(out[0]["action"]["selector"], ".sponsored");
    }

    #[test]
    fn comments_and_blank_lines_are_skipped_not_counted_as_errors() {
        let (rules, errors) = convert_text("! a comment\n\n[Adblock Plus 2.0]\n||x.test^\n");
        assert_eq!(rules.len(), 1);
        assert_eq!(errors, 0);
    }

    #[test]
    fn unconvertible_lines_are_counted() {
        let (_, errors) = convert_text("||x.test^$websocket,badmodifier\n");
        assert!(errors >= 1);
    }

    #[test]
    fn ffi_roundtrip_and_free() {
        let text = "||ads.example.com^\n";
        let mut count = 0usize;
        let mut errs = 0usize;
        unsafe {
            let p = nook_adblock_convert_to_content_blocking(
                text.as_ptr() as *const c_char,
                text.len(),
                &mut count,
                &mut errs,
            );
            assert!(!p.is_null());
            let json = std::ffi::CStr::from_ptr(p).to_str().unwrap().to_owned();
            assert!(json.starts_with('['));
            assert_eq!(count, 1);
            assert_eq!(errs, 0);
            nook_adblock_string_free(p);
            nook_adblock_string_free(ptr::null_mut());

            assert!(nook_adblock_convert_to_content_blocking(
                ptr::null(),
                0,
                ptr::null_mut(),
                ptr::null_mut()
            )
            .is_null());
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd Nook/ThirdParty/AdblockRustFFI && cargo test content_blocking_ffi
```

Expected: FAIL to compile. The module is not declared in `lib.rs`, `guard` is private, and `serde_json` is not a dependency.

- [ ] **Step 3: Wire the module and its dependencies**

In `Nook/ThirdParty/AdblockRustFFI/Cargo.toml`, add to `[dependencies]`:

```toml
serde_json = "1"
```

In `Nook/ThirdParty/AdblockRustFFI/src/lib.rs`, change the `guard` helper from private to crate-visible and declare the module. Replace:

```rust
// panic = "abort" in release; catch_unwind still guards debug/test builds.
fn guard<T>(f: impl FnOnce() -> T, fallback: T) -> T {
```

with:

```rust
pub(crate) mod content_blocking_ffi;

// panic = "abort" in release; catch_unwind still guards debug/test builds.
pub(crate) fn guard<T>(f: impl FnOnce() -> T, fallback: T) -> T {
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd Nook/ThirdParty/AdblockRustFFI && cargo test content_blocking_ffi
```

Expected: PASS, six tests.

If `exception_rule_becomes_ignore_previous_rules` or `cosmetic_rule_becomes_css_display_none` fails on the action type, print the actual JSON and adjust the assertion to the crate's real output. Those two assertions encode my reading of the crate rather than a requirement. Do not change the conversion to satisfy the test.

If `unconvertible_lines_are_counted` passes with `errors == 0`, the modifier chosen is convertible. Substitute a modifier the crate rejects, found by reading `CbRuleCreationFailure` in the crate source.

- [ ] **Step 5: Declare the functions in the C header**

In `Nook/ThirdParty/AdblockRustFFI/include/nook_adblock.h`, insert before the closing `#ifdef __cplusplus` guard:

```c
/// Convert ABP/uBlock filter text (UTF-8, not NUL-terminated) into a
/// NUL-terminated UTF-8 JSON array of WKContentRuleList rule objects.
/// Writes the converted rule count to *out_rule_count and the number of lines
/// that failed to convert to *out_error_count; either pointer may be NULL.
/// Returns NULL on a NULL or non-UTF-8 input. Free with nook_adblock_string_free.
char *nook_adblock_convert_to_content_blocking(const char *rules_utf8, size_t rules_len, size_t *out_rule_count, size_t *out_error_count);

/// Free a string returned by any char*-returning function in this library.
/// NULL is a no-op.
void nook_adblock_string_free(char *s);
```

- [ ] **Step 6: Rebuild the static library**

```bash
cd Nook/ThirdParty/AdblockRustFFI && ./build.sh
```

Expected: `cargo test --release` passes, then `ls -lh` prints the rebuilt `lib/macos-arm64/libnook_adblock.a`. Note the size; Task 9 compares against it.

- [ ] **Step 7: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git status --porcelain
git add Nook/ThirdParty/AdblockRustFFI/Cargo.toml Nook/ThirdParty/AdblockRustFFI/Cargo.lock \
        Nook/ThirdParty/AdblockRustFFI/src/lib.rs \
        Nook/ThirdParty/AdblockRustFFI/src/content_blocking_ffi.rs \
        Nook/ThirdParty/AdblockRustFFI/include/nook_adblock.h \
        Nook/ThirdParty/AdblockRustFFI/lib/macos-arm64/libnook_adblock.a
git commit -m "feat(adblock): FFI for filter-to-WKContentRuleList conversion

adblock::content_blocking is the converter Brave wrote for Brave iOS. Exposing
it here is the first half of removing AdGuard's GPL-3.0 SafariConverterLib.

Assisted by Claude Code."
```

---

### Task 3: Cosmetic lookup FFI

**Files:**
- Create: `Nook/ThirdParty/AdblockRustFFI/src/cosmetic_ffi.rs`
- Modify: `Nook/ThirdParty/AdblockRustFFI/src/lib.rs`
- Modify: `Nook/ThirdParty/AdblockRustFFI/include/nook_adblock.h`

**Interfaces:**
- Consumes: `guard` and `nook_adblock_string_free` from Task 2.
- Produces:
  - `char *nook_adblock_cosmetic_for_url(void *engine, const char *url)`: NUL-terminated UTF-8 JSON, or NULL when nothing applies. Free with `nook_adblock_string_free`.

**One function, not three.** `CosmeticFilterCache` is `pub(crate)` and not
reachable. The crate's public cosmetic API is `Engine::url_cosmetic_resources`,
and `nook_adblock_engine_from_rules` already builds an `Engine`. So the caller
builds one engine, uses it for both matching and cosmetics, and frees it with
the existing `nook_adblock_engine_free`. No second opaque type, no
`ResourceStorage` to manage, no URL parsing on the Rust side.

The JSON object returned by `nook_adblock_cosmetic_for_url` has exactly these keys:

```json
{
  "hide_selectors": ["string"],
  "procedural_actions": ["string (each itself a JSON object)"],
  "injected_script": "string",
  "exceptions": ["string"],
  "generichide": false
}
```

**Context:** `AdvancedRulesEngine.configuration(for:topUrl:)` returns a dictionary that `nook-advanced-blocking.js` consumes today, keyed `css`, `extendedCss`, `js`, `scriptlets`, `engineTimestamp`. Task 5 translates between the shape above and a new script's expectations. This task produces the crate's native shape and translates nothing.

**Thread safety:** `CosmeticFilterCache` is `Send` but not `Sync`, exactly like `Engine`. The header must say so, and the Swift wrapper in Task 5 confines it.

- [ ] **Step 1: Write the failing test**

Create `Nook/ThirdParty/AdblockRustFFI/src/cosmetic_ffi.rs`:

```rust
//! C ABI over adblock::cosmetic_filter_cache: per-URL cosmetic rule lookup.

use crate::guard;
use adblock::cosmetic_filter_cache::CosmeticFilterCache;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

/// Build a cosmetic filter cache from ABP/uBlock filter text (UTF-8, not
/// NUL-terminated). Returns NULL on failure. Free with nook_adblock_cosmetic_free.
///
/// THREAD SAFETY: the returned pointer is Send but not Sync. Confine it to one
/// actor or queue, as with the engine pointer.
#[no_mangle]
pub unsafe extern "C" fn nook_adblock_cosmetic_from_rules(
    rules_utf8: *const c_char,
    rules_len: usize,
) -> *mut CosmeticFilterCache {
    if rules_utf8.is_null() {
        return ptr::null_mut();
    }
    let bytes = std::slice::from_raw_parts(rules_utf8 as *const u8, rules_len);
    let Ok(text) = std::str::from_utf8(bytes) else {
        return ptr::null_mut();
    };
    guard(
        || {
            let cache = CosmeticFilterCache::from_rules(text.lines());
            Box::into_raw(Box::new(cache))
        },
        ptr::null_mut(),
    )
}

/// Cosmetic resources for one URL, as a NUL-terminated UTF-8 JSON object with
/// keys hide_selectors, procedural_actions, injected_script and generichide.
/// Returns NULL when nothing applies or on bad input.
/// Free with nook_adblock_string_free.
#[no_mangle]
pub unsafe extern "C" fn nook_adblock_cosmetic_for_url(
    cache: *mut CosmeticFilterCache,
    url: *const c_char,
    generic_hide: bool,
) -> *mut c_char {
    if cache.is_null() || url.is_null() {
        return ptr::null_mut();
    }
    let Ok(url) = CStr::from_ptr(url).to_str() else {
        return ptr::null_mut();
    };
    let cache = &*cache;
    guard(
        || {
            let Some(host) = host_of(url) else {
                return ptr::null_mut();
            };
            let domain = domain_of(&host);
            let res = cache.hostname_cosmetic_resources(&host, &domain, generic_hide);
            if res.hide_selectors.is_empty()
                && res.procedural_actions.is_empty()
                && res.injected_script.is_empty()
            {
                return ptr::null_mut();
            }
            let Ok(json) = serde_json::to_string(&res) else {
                return ptr::null_mut();
            };
            match CString::new(json) {
                Ok(c) => c.into_raw(),
                Err(_) => ptr::null_mut(),
            }
        },
        ptr::null_mut(),
    )
}

/// Free a cache returned by nook_adblock_cosmetic_from_rules. NULL is a no-op.
#[no_mangle]
pub unsafe extern "C" fn nook_adblock_cosmetic_free(cache: *mut CosmeticFilterCache) {
    if !cache.is_null() {
        drop(Box::from_raw(cache));
    }
}

/// Host component of an absolute URL, lowercased, without port or userinfo.
fn host_of(url: &str) -> Option<String> {
    let rest = url.split_once("://").map(|(_, r)| r).unwrap_or(url);
    let authority = rest.split(['/', '?', '#']).next()?;
    let authority = authority.rsplit_once('@').map(|(_, h)| h).unwrap_or(authority);
    let host = authority.split(':').next()?;
    if host.is_empty() {
        None
    } else {
        Some(host.to_ascii_lowercase())
    }
}

/// Registrable domain for a host, via the crate's own resolver so it matches
/// the semantics the filter lists were written against.
fn domain_of(host: &str) -> String {
    let start = adblock::url_parser::get_host_domain(host);
    host[start..].to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;

    const RULES: &str = "example.com##.ad-banner\n##.generic-ad\n";

    fn lookup(url: &str, generic_hide: bool) -> Option<Value> {
        let c = CString::new(url).unwrap();
        unsafe {
            let cache = nook_adblock_cosmetic_from_rules(RULES.as_ptr() as *const c_char, RULES.len());
            assert!(!cache.is_null());
            let p = nook_adblock_cosmetic_for_url(cache, c.as_ptr(), generic_hide);
            let out = if p.is_null() {
                None
            } else {
                let s = CStr::from_ptr(p).to_str().unwrap().to_owned();
                nook_adblock_string_free(p);
                Some(serde_json::from_str(&s).unwrap())
            };
            nook_adblock_cosmetic_free(cache);
            out
        }
    }

    #[test]
    fn hostname_rule_applies_to_its_host() {
        let v = lookup("https://example.com/page", false).expect("should match");
        let hidden = v["hide_selectors"].as_array().unwrap();
        assert!(hidden.iter().any(|s| s == ".ad-banner"));
    }

    #[test]
    fn hostname_rule_does_not_apply_elsewhere() {
        let v = lookup("https://other.test/page", false).expect("generic rule still applies");
        let hidden = v["hide_selectors"].as_array().unwrap();
        assert!(!hidden.iter().any(|s| s == ".ad-banner"));
    }

    #[test]
    fn subdomain_inherits_the_hostname_rule() {
        let v = lookup("https://www.example.com/page", false).expect("should match");
        let hidden = v["hide_selectors"].as_array().unwrap();
        assert!(hidden.iter().any(|s| s == ".ad-banner"));
    }

    #[test]
    fn host_parsing_handles_port_and_userinfo() {
        assert_eq!(host_of("https://user:pw@Example.COM:8443/x"), Some("example.com".into()));
        assert_eq!(host_of("https://example.com"), Some("example.com".into()));
        assert_eq!(host_of("not a url"), Some("not a url".into()));
        assert_eq!(host_of("https:///x"), None);
    }

    #[test]
    fn null_and_empty_inputs_are_safe() {
        unsafe {
            assert!(nook_adblock_cosmetic_from_rules(ptr::null(), 0).is_null());
            let c = CString::new("https://example.com/").unwrap();
            assert!(nook_adblock_cosmetic_for_url(ptr::null_mut(), c.as_ptr(), false).is_null());
            let cache = nook_adblock_cosmetic_from_rules(RULES.as_ptr() as *const c_char, RULES.len());
            assert!(nook_adblock_cosmetic_for_url(cache, ptr::null(), false).is_null());
            nook_adblock_cosmetic_free(cache);
            nook_adblock_cosmetic_free(ptr::null_mut());
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd Nook/ThirdParty/AdblockRustFFI && cargo test cosmetic_ffi
```

Expected: FAIL to compile, module not declared.

- [ ] **Step 3: Declare the module**

In `Nook/ThirdParty/AdblockRustFFI/src/lib.rs`, next to the Task 2 declaration:

```rust
pub(crate) mod content_blocking_ffi;
pub(crate) mod cosmetic_ffi;
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
cd Nook/ThirdParty/AdblockRustFFI && cargo test cosmetic_ffi
```

Expected: PASS, five tests.

Two API details in this task are my reading of the crate rather than verified calls. If the compiler disagrees, believe the compiler:

- `CosmeticFilterCache::from_rules` takes `impl IntoIterator<Item = impl AsRef<str>>`. If the real signature differs, adapt the call rather than the test.
- `adblock::url_parser::get_host_domain` may be private or named differently. If it is not reachable, replace `domain_of` with the last two labels of the host (`host.rsplit('.').take(2)` reversed and rejoined) and add a `ponytail:` comment naming the ceiling: `// ponytail: naive eTLD+1, swap for a public-suffix lookup if multi-label TLDs misfire`. Do not add a new crate dependency for this.
- `UrlSpecificResources` must be `Serialize` for `serde_json::to_string` to work. The crate derives `Serialize` on it. If it does not, build the JSON object by hand with `serde_json::json!`.

- [ ] **Step 5: Declare the functions in the C header**

In `Nook/ThirdParty/AdblockRustFFI/include/nook_adblock.h`, after the Task 2 declarations:

```c
/// Build a cosmetic filter cache from ABP/uBlock filter text (UTF-8, not
/// NUL-terminated). Returns NULL on failure.
///
/// THREAD SAFETY: as with an engine pointer, a cache pointer is NOT thread-safe.
/// The caller must serialize all calls on a given cache.
void *nook_adblock_cosmetic_from_rules(const char *rules_utf8, size_t rules_len);

/// Cosmetic resources for one URL, as a NUL-terminated UTF-8 JSON object with
/// keys hide_selectors (array of string), procedural_actions (array of string,
/// each a JSON object), injected_script (string) and generichide (bool).
/// Returns NULL when nothing applies or on bad input.
/// Free with nook_adblock_string_free.
char *nook_adblock_cosmetic_for_url(void *cache, const char *url, bool generic_hide);

/// Free a cache returned by nook_adblock_cosmetic_from_rules. NULL is a no-op.
void nook_adblock_cosmetic_free(void *cache);
```

- [ ] **Step 6: Rebuild and commit**

```bash
cd Nook/ThirdParty/AdblockRustFFI && ./build.sh
cd "$(git rev-parse --show-toplevel)"
git status --porcelain
git add Nook/ThirdParty/AdblockRustFFI/src/lib.rs \
        Nook/ThirdParty/AdblockRustFFI/src/cosmetic_ffi.rs \
        Nook/ThirdParty/AdblockRustFFI/include/nook_adblock.h \
        Nook/ThirdParty/AdblockRustFFI/lib/macos-arm64/libnook_adblock.a
git commit -m "feat(adblock): FFI for per-URL cosmetic rule lookup

CosmeticFilterCache::hostname_cosmetic_resources is the lookup AdvancedRules
does today through AdGuard's FilterEngine. Second half of the GPL removal.

Assisted by Claude Code."
```

---

### Task 4: Swift wrapper for conversion, and swap the compiler

**Files:**
- Create: `Nook/Managers/ContentBlockerManager/RustContentBlockingConverter.swift`
- Modify: `Nook/Managers/ContentBlockerManager/ContentRuleListCompiler.swift:14-18` (imports), `:72-95` (the conversion block)

**Interfaces:**
- Consumes: `nook_adblock_convert_to_content_blocking`, `nook_adblock_string_free` from Task 2.
- Produces: `RustContentBlockingConverter.convert(rules: [String]) -> RustContentBlockingConverter.Output`, where `Output` has `entries: [[String: Any]]`, `ruleCount: Int`, `errorCount: Int`. A `nonisolated` static function, safe to call from a detached task.

**Context:** `ContentRuleListCompiler.compile` currently returns `CompilationResult` carrying `advancedRulesText: String?`, which `ContentBlockerManager.rebuild()` passes to `advancedRulesEngine.build(rulesText:reuseSerialized:)` at line 186. The new cosmetic engine builds from the raw filter rules rather than from a converter-produced text blob, so `advancedRulesText` loses its meaning. Keep the field and the call site intact in this task and retire them in Task 6, so that each task leaves a building app.

The cache is keyed by SHA-256 of the input rules. Changing the converter does not change that hash, so the first launch after this task loads a cache compiled by AdGuard's converter and skips conversion entirely. Bump the cache prefix so the first run after the swap actually recompiles.

- [ ] **Step 1: Write the converter wrapper**

Create `Nook/Managers/ContentBlockerManager/RustContentBlockingConverter.swift`:

```swift
//
//  RustContentBlockingConverter.swift
//  Nook
//
//  Converts ABP/uBlock filter rules into WKContentRuleList JSON via
//  adblock-rust (MPL-2.0). Replaces AdGuard's SafariConverterLib, which is
//  GPL-3.0 and therefore cannot ship through the App Store.
//
//  Foundation only; nothing here is AppKit-specific.
//

import Foundation
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "ContentBlocker")

enum RustContentBlockingConverter {

    struct Output {
        let entries: [[String: Any]]
        let ruleCount: Int
        let errorCount: Int
    }

    /// Convert filter rules to WKContentRuleList entries.
    /// Safe to call off the main actor; holds no shared state.
    nonisolated static func convert(rules: [String]) -> Output {
        let text = rules.joined(separator: "\n")
        var ruleCount = 0
        var errorCount = 0

        let json: String? = text.withCString { ptr -> String? in
            guard let raw = nook_adblock_convert_to_content_blocking(
                ptr, strlen(ptr), &ruleCount, &errorCount
            ) else { return nil }
            defer { nook_adblock_string_free(raw) }
            return String(cString: raw)
        }

        guard let json, let data = json.data(using: .utf8) else {
            log.error("adblock-rust conversion returned nothing")
            return Output(entries: [], ruleCount: 0, errorCount: rules.count)
        }
        guard let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            log.error("adblock-rust conversion produced unparseable JSON")
            return Output(entries: [], ruleCount: 0, errorCount: rules.count)
        }
        return Output(entries: entries, ruleCount: ruleCount, errorCount: errorCount)
    }
}
```

- [ ] **Step 2: Swap the conversion call**

In `Nook/Managers/ContentBlockerManager/ContentRuleListCompiler.swift`, delete the import at line 18:

```swift
import ContentBlockerConverter
```

Replace lines 72 through 95 (from the `cbLog.info("Cache miss...` line through the `cbLog.info("SafariConverterLib: ...` line) with:

```swift
        cbLog.info("Cache miss: converting \(rules.count) rules via adblock-rust")

        let converted = await Task.detached(priority: .userInitiated) {
            RustContentBlockingConverter.convert(rules: rules)
        }.value

        let jsonEntries = converted.entries
        let advancedText: String? = nil
        cbLog.info("adblock-rust: \(rules.count) source, \(converted.ruleCount) safari, \(converted.errorCount) errors")
```

Update the header comment at lines 5 and 6 to name adblock-rust rather than SafariConverterLib, and update the doc comment at line 50.

- [ ] **Step 3: Bump the cache prefix so the first run recompiles**

In the same file, change line 26:

```swift
    private static let storeIdentifierPrefix = "NookAdBlockerRust"
```

The old `NookAdBlocker_*` lists stay in the store until `removeOldRuleLists` runs, and that function filters on the prefix, so it no longer sees them. Extend it to clean both. Replace the body of `removeOldRuleLists` at line 222:

```swift
        for id in ids where id.hasPrefix(storeIdentifierPrefix) || id.hasPrefix("NookAdBlocker_") {
```

Also invalidate the stale hash file, since a cache hit would otherwise skip conversion on first launch. In `loadFromCache`, immediately after the `guard let storedHash` block at line 161, add:

```swift
        // The converter changed; a hash written by SafariConverterLib says nothing
        // about rule lists this build can use.
        guard FileManager.default.fileExists(atPath: converterStampFile.path) else { return nil }
```

Add the stamp file next to the other cache URLs at line 46:

```swift
    /// Written only by saveCache. Its absence means the cache predates the adblock-rust swap.
    private static var converterStampFile: URL { cacheDir.appendingPathComponent("converter-adblock-rust") }
```

And write it in `saveCache`, after line 189:

```swift
        try? Data().write(to: converterStampFile)
```

- [ ] **Step 4: Build**

```bash
cd "$(git rev-parse --show-toplevel)"
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`. `ContentBlockerConverter` is still a package dependency at this point and `AdvancedRulesEngine.swift` still imports it, so the link succeeds.

- [ ] **Step 5: Run and read the conversion log**

```bash
open build/Build/Products/Debug/Nook.app
/usr/bin/log stream --level info --predicate 'subsystem == "com.baingurley.nook" && category == "ContentBlocker"'
```

Expected: a line reading `adblock-rust: N source, M safari, E errors`, then `Compiled K rule list(s) from J entries`.

**Record `M`, `E`, `J` and `K`.** Task 9 compares them against the SafariConverterLib numbers. If `M` is zero, conversion failed silently and the next task is worthless; stop and diagnose before continuing.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git status --porcelain
git add Nook/Managers/ContentBlockerManager/RustContentBlockingConverter.swift \
        Nook/Managers/ContentBlockerManager/ContentRuleListCompiler.swift
git commit -m "feat(adblock): convert filter rules with adblock-rust

The compiler keeps its 30K chunking, SHA-256 cache and store management and
swaps only the converter. A new store prefix and a stamp file force one
recompile, since the old hash describes lists AdGuard's converter produced.

Assisted by Claude Code."
```

---

### Task 5: Swift cosmetic engine

**Files:**
- Create: `Nook/Managers/ContentBlockerManager/CosmeticFilterEngine.swift`

**Interfaces:**
- Consumes: `nook_adblock_engine_from_rules` and `nook_adblock_engine_free` (which already existed), plus `nook_adblock_cosmetic_for_url` and `nook_adblock_string_free` from Tasks 2 and 3.
- Produces:
  - `actor CosmeticFilterEngine`
  - `func build(rules: [String]) async`
  - `func configuration(for pageUrl: URL, topUrl: URL?) async -> [String: Any]?`
  - `func clear() async`

The returned dictionary has exactly these keys, which Task 7's script consumes:

```
"css"        [String]  selectors to hide with display: none !important
"extendedCss" [[String: Any]]  procedural filters, each {selector, action?}
"js"         String    script text to run, empty when none
```

**Context:** `AdvancedRulesEngine` is `@MainActor` and holds a `nonisolated(unsafe) var webExtension`. The crate's cache is `Send` but not `Sync`, so an `actor` is the correct confinement and removes the `nonisolated(unsafe)`. `ContentBlockerManager.handleAdvancedBlockingMessage` at line 442 calls `configuration` synchronously inside a reply handler, so Task 6 has to bridge that; this task exposes the async form and nothing else.

`topUrl` exists in the current signature for subframe lookups. adblock-rust's cosmetic cache keys on the frame's own host, so `topUrl` is accepted and unused. Keep the parameter so the call sites do not churn, and say why in a comment.

- [ ] **Step 1: Write the engine**

Create `Nook/Managers/ContentBlockerManager/CosmeticFilterEngine.swift`:

```swift
//
//  CosmeticFilterEngine.swift
//  Nook
//
//  Per-URL cosmetic rule lookup over adblock-rust's CosmeticFilterCache
//  (MPL-2.0). Replaces AdGuard's FilterEngine, which is GPL-3.0.
//
//  The cache pointer is Send but not Sync, so this is an actor. Foundation
//  only; nothing here is AppKit-specific.
//

import Foundation
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "AdvancedRules")

actor CosmeticFilterEngine {

    private var engine: UnsafeMutableRawPointer?

    deinit {
        if let engine { nook_adblock_engine_free(engine) }
    }

    /// Build or rebuild the cache. Replaces any previous one.
    func build(rules: [String]) async {
        clearEngine()
        guard !rules.isEmpty else {
            log.info("No filter rules; cosmetic engine cleared")
            return
        }
        let start = CFAbsoluteTimeGetCurrent()
        let text = rules.joined(separator: "\n")
        engine = text.withCString { nook_adblock_engine_from_rules($0, strlen($0)) }
        if engine == nil {
            log.error("Failed to build the cosmetic filter cache")
            return
        }
        log.info("Cosmetic engine built in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - start), privacy: .public)s")
    }

    func clear() async {
        clearEngine()
    }

    /// Cosmetic configuration for a frame, or nil when nothing applies.
    /// `topUrl` is accepted for call-site compatibility and deliberately unused:
    /// adblock-rust keys cosmetic lookups on the frame's own host, so a subframe
    /// gets its own rules rather than the top document's.
    func configuration(for pageUrl: URL, topUrl: URL?) async -> [String: Any]? {
        guard let engine else { return nil }
        let raw: String? = pageUrl.absoluteString.withCString { urlPtr in
            guard let p = nook_adblock_cosmetic_for_url(engine, urlPtr) else { return nil }
            defer { nook_adblock_string_free(p) }
            return String(cString: p)
        }
        guard let raw,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let hide = object["hide_selectors"] as? [String] ?? []
        let script = object["injected_script"] as? String ?? ""
        let procedural = (object["procedural_actions"] as? [String] ?? []).compactMap { entry -> [String: Any]? in
            guard let d = entry.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        }

        if hide.isEmpty && procedural.isEmpty && script.isEmpty { return nil }
        return ["css": hide, "extendedCss": procedural, "js": script]
    }

    private func clearEngine() {
        if let engine { nook_adblock_engine_free(engine) }
        engine = nil
    }
}
```

- [ ] **Step 2: Build**

```bash
cd "$(git rev-parse --show-toplevel)"
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`. Nothing calls this type yet; this step proves it compiles against the header.

If the compiler objects to `nook_adblock_engine_free` in `deinit` because `deinit` cannot access actor-isolated state, move the free into `clear()` and add a `// ponytail:` comment noting the engine leaks if the actor is dropped without `clear()`, which in practice it is not, since `ContentBlockerManager` holds one for the process lifetime.

- [ ] **Step 3: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git status --porcelain
git add Nook/Managers/ContentBlockerManager/CosmeticFilterEngine.swift
git commit -m "feat(adblock): cosmetic lookup actor over adblock-rust

An actor rather than @MainActor plus nonisolated(unsafe): the crate's cache is
Send but not Sync, which is exactly what actor isolation is for.

Assisted by Claude Code."
```

---

### Task 6: Point AdvancedRulesEngine at the new engine

**Files:**
- Modify: `Nook/Managers/ContentBlockerManager/AdvancedRulesEngine.swift:15-19` (imports), `:33-101` (engine and lookup)
- Modify: `Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift:186` (build call), `:442` (subframe lookup)
- Modify: `Nook/Managers/ContentBlockerManager/ContentRuleListCompiler.swift` (retire `advancedRulesText`)

**Interfaces:**
- Consumes: `CosmeticFilterEngine` from Task 5.
- Produces: `AdvancedRulesEngine` keeps `scriptMarker`, `configScriptMarker`, `messageHandlerName`, `staticUserScripts`, `requestStatsScriptMarker`, `requestStatsScript(token:)` unchanged. `build(rulesText:reuseSerialized:)` becomes `build(rules: [String]) async`. `configuration(for:topUrl:)` becomes `async`. `configUserScript(for:)` becomes `async`.

**Context:** Making `configuration` async ripples to two call sites. Line 308 (`configUserScript`) is already inside an async context or can be made one. Line 442 is inside `WKScriptMessageHandlerWithReply`'s non-async callback, which takes a `replyHandler` closure; wrap the lookup in a `Task` and call `replyHandler` from inside it. That is legal: the reply handler may be called after the callback returns.

This is the task most likely to need adjustment against the real code, because it touches three files and two of them are partly outside what this plan has read. Read all three call sites fully before editing.

- [ ] **Step 1: Replace the engine in AdvancedRulesEngine**

In `Nook/Managers/ContentBlockerManager/AdvancedRulesEngine.swift`:

Delete the imports at lines 18 and 19:

```swift
import ContentBlockerConverter
import FilterEngine
```

Replace lines 33 through 38 (the `webExtension` property and `containerURL`) with:

```swift
    private let cosmetic = CosmeticFilterEngine()
```

Replace the entire `build(rulesText:reuseSerialized:)` function, lines 42 through 68, with:

```swift
    /// Build (or rebuild) the cosmetic lookup engine from the raw filter rules.
    /// adblock-rust parses the original filter syntax directly, so there is no
    /// intermediate "advanced rules text" the way SafariConverterLib produced one.
    func build(rules: [String]) async {
        await cosmetic.build(rules: rules)
    }
```

Replace `configuration(for:topUrl:)`, lines 74 through 84, with:

```swift
    /// JSON-ready configuration for a frame, or nil when nothing applies.
    /// `topUrl` is the top-level document URL; pass nil for the main frame.
    func configuration(for pageUrl: URL, topUrl: URL?) async -> [String: Any]? {
        await cosmetic.configuration(for: pageUrl, topUrl: topUrl)
    }
```

Replace `configUserScript(for:)`, lines 89 through 101, with:

```swift
    func configUserScript(for pageUrl: URL) async -> WKUserScript {
        var json = "null"
        if let conf = await configuration(for: pageUrl, topUrl: nil),
           let data = try? JSONSerialization.data(withJSONObject: conf),
           let text = String(data: data, encoding: .utf8) {
            json = text
        }
        return WKUserScript(
            source: Self.configScriptMarker + "window.__nookCosmeticConfig = \(json);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }
```

Update the file header comment at lines 5 through 10 to describe adblock-rust and `nook-cosmetic.js` rather than SafariConverterLib and AdGuard.

- [ ] **Step 2: Update the build call site**

In `Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift`, replace line 186:

```swift
        await advancedRulesEngine.build(rules: rules)
```

- [ ] **Step 3: Update the subframe lookup call site**

In the same file, replace line 442 and the two lines after it:

```swift
        Task { [advancedRulesEngine] in
            let conf = await advancedRulesEngine.configuration(
                for: pageUrl,
                topUrl: message.frameInfo.isMainFrame ? nil : topUrl
            )
            cbLog.info("frame lookup \(pageUrl.host ?? "-", privacy: .public) main=\(message.frameInfo.isMainFrame) rules=\(conf == nil ? 0 : 1, privacy: .public)")
            replyHandler(conf, nil)
        }
```

- [ ] **Step 4: Update the main-frame config call site**

Read `ContentBlockerManager.swift` around line 308 in full before editing. Change:

```swift
        let config = exempt ? nil : advancedRulesEngine.configUserScript(for: url)
```

to await the call. If the enclosing function is not `async`, make it `async` and update its callers, or wrap the work in a `Task`, whichever the surrounding code makes natural. Do not add a semaphore or `Task { }.wait()` style bridge.

- [ ] **Step 5: Retire advancedRulesText**

In `Nook/Managers/ContentBlockerManager/ContentRuleListCompiler.swift`:

- Remove `advancedRulesText` from `CompilationResult` (line 30) and from both constructions of it (lines 56, 131, 183).
- Remove `advancedRulesFile` (line 46), the read at line 181, the writes at lines 190 through 194, and the delete in `clearCache` at line 200.
- Remove the `advancedText` local introduced in Task 4 and its use in `saveCache`.
- Change `saveCache(hash:chunkCount:advancedRulesText:)` to `saveCache(hash:chunkCount:)`.
- `fromCache` and `reuseSerialized` no longer feed anything, since the cosmetic engine rebuilds from rules in under a second. Leave `fromCache` in place; it is still logged.

- [ ] **Step 6: Build**

```bash
cd "$(git rev-parse --show-toplevel)"
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30
```

Expected: `BUILD SUCCEEDED`. `ContentBlockerConverter` is still a package dependency but nothing imports it now.

- [ ] **Step 7: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git status --porcelain
git add Nook/Managers/ContentBlockerManager/AdvancedRulesEngine.swift \
        Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift \
        Nook/Managers/ContentBlockerManager/ContentRuleListCompiler.swift
git commit -m "refactor(adblock): look cosmetic rules up through adblock-rust

AdvancedRulesEngine keeps its markers and static scripts and swaps its lookup.
adblock-rust parses filter syntax directly, so advancedRulesText and the
serialized-engine warm start both go away.

Assisted by Claude Code."
```

---

### Task 7: Replace the content script

**Files:**
- Create: `Nook/Managers/ContentBlockerManager/Resources/nook-cosmetic.js`
- Delete: `Nook/Managers/ContentBlockerManager/Resources/nook-advanced-blocking.js`
- Delete: `Nook/Managers/ContentBlockerManager/Resources/BUILD-advanced-blocking.md`
- Modify: `Nook/Managers/ContentBlockerManager/AdvancedRulesEngine.swift:109-113`

**Interfaces:**
- Consumes: `window.__nookCosmeticConfig` set by Task 6's `configUserScript`, and the `nookAdvancedBlocking` message handler for subframes.
- Produces: no Swift interface. The script is a leaf.

**Context:** The old script bundled `@adguard/safari-extension`, `@adguard/extended-css`, and `@adguard/scriptlets`, all GPL-3.0, built through esbuild. The replacement is hand-written, ships as source, and needs no build step, which is why `BUILD-advanced-blocking.md` goes too.

Scope for this task: `css` selectors become one stylesheet, and `extendedCss` entries that are expressible as plain CSS become part of it. True procedural operators are skipped with a debug log. `js` is not executed at all, because the scriptlet bodies that would populate it are not shipping in phase 1. That matches the spec.

The script must never throw into the page.

- [ ] **Step 1: Write the script**

Create `Nook/Managers/ContentBlockerManager/Resources/nook-cosmetic.js`:

```js
// Nook Content Blocker
//
// Applies cosmetic filter rules from adblock-rust (MPL-2.0). Runs in the page
// world at document start in every frame.
//
// Main frame: window.__nookCosmeticConfig is set synchronously by a config
// user script before this runs, so there is no round trip. Subframes ask the
// nookAdvancedBlocking message handler.
//
// Scope: plain hide selectors, plus procedural filters expressible as CSS.
// True procedural operators (:has-text, :upward, :matches-css) are skipped.
// Scriptlets are not executed in this build.

(function () {
  if (window.__nookCosmeticLoaded) return;
  window.__nookCosmeticLoaded = true;

  var verbose = window.__nookCosmeticVerbose === true;

  function log() {
    if (!verbose) return;
    try {
      console.log.apply(console, ['[Nook AdBlock]'].concat([].slice.call(arguments)));
    } catch (e) {}
  }

  // A procedural filter is CSS-expressible when every selector operator is a
  // plain CSS selector. Anything else needs a JS evaluator we do not ship.
  function proceduralToCss(filter) {
    if (!filter || !Array.isArray(filter.selector)) return null;
    var parts = [];
    for (var i = 0; i < filter.selector.length; i++) {
      var op = filter.selector[i];
      if (!op || typeof op.CssSelector !== 'string') return null;
      parts.push(op.CssSelector);
    }
    if (!parts.length) return null;
    var selector = parts.join('');
    var action = filter.action;
    if (!action) return selector + '{display:none !important;}';
    if (typeof action.Style === 'string') return selector + '{' + action.Style + '}';
    return null;
  }

  function buildCss(config) {
    var chunks = [];
    var hide = config && config.css;
    if (Array.isArray(hide) && hide.length) {
      chunks.push(hide.join(',\n') + '{display:none !important;}');
    }
    var procedural = config && config.extendedCss;
    if (Array.isArray(procedural)) {
      var skipped = 0;
      for (var i = 0; i < procedural.length; i++) {
        var css = proceduralToCss(procedural[i]);
        if (css) chunks.push(css);
        else skipped++;
      }
      if (skipped) log('skipped', skipped, 'procedural filter(s) needing a JS evaluator');
    }
    return chunks.join('\n');
  }

  function inject(css) {
    if (!css) return;
    try {
      var style = document.createElement('style');
      style.setAttribute('type', 'text/css');
      style.textContent = css;
      var parent = document.head || document.documentElement;
      if (parent) {
        parent.appendChild(style);
        return;
      }
      // document.documentElement can be null at document start in a frame that
      // has not parsed its root element yet. Retry once the DOM exists.
      document.addEventListener('DOMContentLoaded', function () {
        try {
          (document.head || document.documentElement).appendChild(style);
        } catch (e) {}
      }, { once: true });
    } catch (e) {
      log('failed to inject stylesheet', e);
    }
  }

  function apply(config) {
    if (!config) return;
    inject(buildCss(config));
  }

  try {
    if (typeof window.__nookCosmeticConfig !== 'undefined') {
      apply(window.__nookCosmeticConfig);
      return;
    }
    var handler =
      window.webkit &&
      window.webkit.messageHandlers &&
      window.webkit.messageHandlers.nookAdvancedBlocking;
    if (!handler) return;
    handler
      .postMessage({ url: location.href })
      .then(apply)
      .catch(function (e) {
        log('subframe lookup failed', e);
      });
  } catch (e) {
    log('startup failed', e);
  }
})();
```

- [ ] **Step 2: Verify the procedural JSON shape before trusting `proceduralToCss`**

`proceduralToCss` reads `op.CssSelector` and `action.Style`, which is serde's
default externally-tagged encoding for the Rust enums `CosmeticFilterOperator`
and `CosmeticFilterAction`. That is a reading of the crate, not a verified fact.

Confirm it:

```bash
cd Nook/ThirdParty/AdblockRustFFI
cargo test cosmetic_ffi -- --nocapture
```

Add a temporary `println!` of one `procedural_actions` entry for a rule that
produces one, such as `example.com##.x:style(color: red)`. Read the real key
names and adjust `proceduralToCss` to match. Remove the `println!` afterwards.

If the shape differs, only `proceduralToCss` changes. The rest of the script
reads `hide_selectors` through the Swift translation in Task 5 and is unaffected.

- [ ] **Step 3: Point the loader at the new file**

In `Nook/Managers/ContentBlockerManager/AdvancedRulesEngine.swift`, replace lines 109 through 113:

```swift
        if let runtime = bundledSource("nook-cosmetic") {
            scripts.append(WKUserScript(source: scriptMarker + runtime, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        } else {
            log.error("nook-cosmetic.js missing from bundle; cosmetic filtering disabled")
        }
```

- [ ] **Step 4: Delete the AdGuard bundle and its build doc**

```bash
cd "$(git rev-parse --show-toplevel)"
git rm Nook/Managers/ContentBlockerManager/Resources/nook-advanced-blocking.js \
       Nook/Managers/ContentBlockerManager/Resources/BUILD-advanced-blocking.md
```

- [ ] **Step 5: Build and verify the script reaches a page**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
open build/Build/Products/Debug/Nook.app
```

With the app running, use the `nook` MCP server:

- `navigateToURL` to a site with known cosmetic rules, for example `https://www.theguardian.com/`.
- `user_scripts` and confirm one script's source begins `// Nook Content Blocker` and contains `__nookCosmeticLoaded`.
- `evaluate` with `document.querySelectorAll('style').length` and confirm at least one style element exists.
- `evaluate` with `window.__nookCosmeticLoaded` and expect `true`.

Expected: all four hold. If `__nookCosmeticLoaded` is undefined, the script did not inject; check that `bundledSource` found the file, which means confirming the Resources directory is in the target's file-system-synchronized group.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git status --porcelain
git add Nook/Managers/ContentBlockerManager/Resources/nook-cosmetic.js \
        Nook/Managers/ContentBlockerManager/AdvancedRulesEngine.swift
git commit -m "feat(adblock): Nook-owned cosmetic content script

Replaces the @adguard/safari-extension bundle, which carried extended-css and
scriptlets and was GPL-3.0 throughout. Hide selectors and CSS-expressible
procedural filters become one stylesheet; true procedural operators and
scriptlets are out of scope for this phase, per the spec.

Drops the esbuild pipeline with it.

Assisted by Claude Code."
```

---

### Task 8: Remove the SafariConverterLib package dependency

**Files:**
- Modify: `Nook.xcodeproj/project.pbxproj`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: nothing. Every import was removed in Tasks 4 and 6.
- Produces: a build that links no GPL-3.0 code.

**Context:** This is the task that makes the whole phase worth doing, and it is the one that proves Tasks 4, 6, and 7 actually removed every use. If the build fails here, something still imports it.

- [ ] **Step 1: Confirm nothing imports it**

```bash
cd "$(git rev-parse --show-toplevel)"
grep -rn "ContentBlockerConverter\|import FilterEngine\|SafariVersion\|WebExtension(" --include="*.swift" . | grep -v "^./build"
```

Expected: no output. Any hit must be resolved before continuing.

- [ ] **Step 2: Remove the package from the Xcode project**

Open `Nook.xcodeproj` in Xcode. Under the project's Package Dependencies, remove `SafariConverterLib`. Under the Nook target's Frameworks and Libraries, remove `ContentBlockerConverter` and `FilterEngine` if either is listed.

Do this in Xcode rather than by editing `project.pbxproj` by hand. The file has four related entries in different sections and a hand edit that misses one produces a project that opens but does not build.

- [ ] **Step 3: Verify the dependency is gone**

```bash
cd "$(git rev-parse --show-toplevel)"
grep -c "SafariConverterLib" Nook.xcodeproj/project.pbxproj
```

Expected: `0`.

- [ ] **Step 4: Clean build, both configurations**

```bash
rm -rf build
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -20
xcodebuild -scheme Nook -configuration Release -arch arm64 -derivedDataPath build-release 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED` twice. Release matters on its own: optimizer-only crashes exist in this codebase, notably the `WKNSArray objectAtIndex:` trap that Debug hides.

- [ ] **Step 5: Update CLAUDE.md**

In the Dependencies table, delete the `SafariConverterLib` row. In the Content Blocker System section, update these bullets:

- `ContentRuleListCompiler`: replace "SafariConverterLib conversion" with "adblock-rust conversion via `RustContentBlockingConverter`".
- `AdvancedRulesEngine`: replace the sentence about wrapping SafariConverterLib's `FilterEngine`/`WebExtension` with one naming `CosmeticFilterEngine` over adblock-rust's `CosmeticFilterCache`, and note that scriptlets and true procedural operators are not applied in this build.
- `Resources/nook-advanced-blocking.js`: replace the whole bullet with one describing `nook-cosmetic.js` as Nook's own script, no build step.
- In the transitive dependency list, remove `swift-psl` and `PunycodeSwift` if nothing else pulls them. Check with `grep -rn "PunycodeSwift\|swift-psl" Nook.xcodeproj/project.pbxproj` first.

In the Dependencies section, add `serde_json` to whatever notes the Rust crate's dependencies, or add a line if none exists.

- [ ] **Step 6: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git status --porcelain
git add Nook.xcodeproj/project.pbxproj CLAUDE.md
git commit -m "build: drop SafariConverterLib

Nook now links no GPL-3.0 code it does not own. The App Store exception in
LICENSE-EXCEPTION.md covers Nook's own source; it could never have reached
AdGuard's.

Assisted by Claude Code."
```

---

### Task 9: Parity gate

**Files:**
- Create: `docs/superpowers/plans/2026-09-17-adblock-rust-parity.md`

**Interfaces:**
- Consumes: the running Release build from Task 8.
- Produces: a written record of what the swap cost, and a go or no-go.

**Context:** This is the gate the spec requires before phase 2 starts. AdGuard tuned their converter for Safari for years; Brave's is production code in Brave iOS. They will not agree, and the disagreements are the point.

This task produces a document and a decision rather than code. Do not skip it because the app appears to work.

- [ ] **Step 1: Record the conversion numbers**

Run the Release build and capture:

```bash
open build-release/Build/Products/Release/Nook.app
/usr/bin/log stream --level info --predicate 'subsystem == "com.baingurley.nook" && category == "ContentBlocker"'
```

Record the `adblock-rust: N source, M safari, E errors` line and the `Compiled K rule list(s) from J entries` line.

Compare against the SafariConverterLib numbers recorded in Task 4 Step 5. A large drop in `M` means rules are being lost. A large rise in `E` means the crate rejects syntax AdGuard accepted.

- [ ] **Step 2: Browse the top twenty sites**

Using the `nook` MCP server, for each site: `navigateToURL`, `wait_for_load`, `screenshot`, then `console` to check for uncaught errors and failed loads.

Cover at minimum: youtube.com, facebook.com, instagram.com, x.com, reddit.com, theguardian.com, cnn.com, nytimes.com, espn.com, amazon.com, ebay.com, imdb.com, wikipedia.org, github.com, stackoverflow.com, weather.com, forbes.com, businessinsider.com, vsco.co, jeep-cj.com.

The last two are the anti-adblock sites from the stealth-redirects work and are the ones most likely to regress.

For each, record: ads visible, layout broken, console errors, and whether the page loaded at all.

- [ ] **Step 3: Check the blocker's own reporting**

For a handful of the sites above, use `blocker_status` and `check_urls` to confirm the blocker reports itself enabled with rule lists loaded, and that known ad URLs still match.

- [ ] **Step 4: Write the parity record**

Create `docs/superpowers/plans/2026-09-17-adblock-rust-parity.md` containing: the two conversion number sets side by side, the twenty-site table, any regression found, and a go or no-go for phase 2.

State a verdict. A document that lists observations without a decision has not gated anything.

- [ ] **Step 5: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git status --porcelain
git add docs/superpowers/plans/2026-09-17-adblock-rust-parity.md
git commit -m "docs: record adblock-rust parity against SafariConverterLib

Assisted by Claude Code."
```

---

### Task 10: Update the exception record

**Files:**
- Modify: `LICENSE-EXCEPTION.md`

**Interfaces:**
- Consumes: the go verdict from Task 9.
- Produces: an accurate statement of what still blocks App Store distribution.

**Context:** `LICENSE-EXCEPTION.md` currently says AdGuard's code is "being replaced". Once Task 8 lands, that is done, and the remaining blockers are the four contributors who have not granted the exception. Leaving a stale claim in a licensing document is the kind of error that matters.

- [ ] **Step 1: Update the third-party section**

In the "Third-party code" section, replace the paragraph naming SafariConverterLib and `@adguard/safari-extension` with a statement that Nook links no GPL-3.0 code it does not own as of the date this task completes, naming the commit from Task 8.

- [ ] **Step 2: Verify the prose lint passes**

```bash
cd "$(git rev-parse --show-toplevel)"
echo '{"tool_input":{"file_path":"LICENSE-EXCEPTION.md"}}' | python3 ~/.claude/hooks/prose-lint.py
```

Expected: exit 0, no output.

- [ ] **Step 3: Commit**

```bash
cd "$(git rev-parse --show-toplevel)"
git status --porcelain
git add LICENSE-EXCEPTION.md
git commit -m "docs: AdGuard is no longer a licensing blocker

Assisted by Claude Code."
```

---

## Corrections made during execution

Three assumptions in the original draft were wrong, found by reading the crate
while running Task 1. Recorded so the same ground is not re-covered.

**`ParsedFilter` does not exist.** `parse_filter` returns
`Result<ParsedLine, FilterParseError>`. Better: `TryFrom<ParsedLine> for
CbRuleEquivalent` exists and covers network and cosmetic filters in one arm, so
`convert_text` never matches on the variant.

**`CosmeticFilterCache` is `pub(crate)`.** The public cosmetic API is
`Engine::url_cosmetic_resources(&self, url: &str) -> UrlSpecificResources`,
which takes a URL rather than a hostname and owns its own `ResourceStorage`.
This collapsed three planned FFI functions into one and deleted the planned
`host_of` helper and `NookCosmeticCache` type outright.

**`css-validation` is required, not optional.** See Task 1. This was the plan's
worst call: skipping it would have shipped invalid CSS selectors into live
stylesheets.

The plan's advice to believe the compiler over the plan was the part that held
up. Tasks 4 to 10 have not been executed and carry the same risk.

## Where this plan departs from the spec

**Conversion granularity.** The spec says to convert per 30,000-rule chunk
because a whole-list conversion returns multi-megabyte JSON across the FFI
boundary in one allocation. This plan converts the whole list in one call.

The reason: `ContentRuleListCompiler` chunks its *output* entries, not its input
rules, so there is no 30,000-rule input chunk to convert. Splitting the input
into arbitrary groups would work, since filter rules convert independently, but
it buys one smaller allocation at the cost of a second chunking scheme that has
to stay in step with the first. The single allocation is freed as soon as
`JSONSerialization` has read it.

Revisit if conversion shows up in a memory profile, which is also exactly when
the iPhone spike in phase 3 would surface it.

## Deferred, deliberately

These are named so they do not get rediscovered as surprises.

**Scriptlets.** `injected_script` is populated by the crate but never executed.
This was researched rather than assumed, on 2026-09-17:

- `brave/adblock-resources` is MPL-2.0, but holds only 17 Brave-specific
  scripts. It is not a scriptlet library and contains no `set-constant`, no
  `abort-on-property-read`, no `json-prune`.
- Brave's real scriptlet library arrives at build time from a uBlock Origin
  submodule. `brave-core-crx-packager/lib/adBlockRustUtils.js` points at
  `submodules/uBlock/src/js/resources/scriptlets.js`, and that file is
  GPL-3.0, Copyright Raymond Hill.
- `@adguard/scriptlets` and `@adguard/safari-extension` are both GPL-3.0.
- `@eyeo/webext-ad-filtering-solution` is GPL-3.0.
- `@ghostery/adblocker` is MPL-2.0 packaging over
  `assets/ublock-origin/resources.json`, which embeds 149 uBO scriptlet bodies
  verbatim.

No permissive general-purpose scriptlet library exists. This matters for a
narrower reason than "avoiding GPL": Nook stays GPL-3.0 and is content to.
What Nook cannot do is attach a section 7 App Store exception to code it does
not own, and Raymond Hill's scriptlets are no more grantable than AdGuard's
converter was.

Writing them is tractable if it becomes necessary. Measured against today's
EasyList, EasyPrivacy, and the uBO lists: 8,247 scriptlet injections across 72
distinct scriptlets, where **10 scriptlets cover about 78% of injections and 20
cover about 93%**. EasyList contains zero `+js()` rules; EasyPrivacy contains 28.
The top six, excluding cookie-banner annoyance lists, are
`abort-on-property-read` (1,165), `set-constant` (1,159),
`abort-current-script` (984), `prevent-window-open` (686),
`prevent-setTimeout` (684), and `prevent-addEventListener` (533). All six are
the same pattern: intercept a property access or a timer or listener
registration, then abort or freeze it. A few hundred lines of independent work
covers the bulk. `trusted-click-element`, `json-prune`, and `href-sanitizer`
are the fiddly ones.

Nook's own site scripts for Facebook, Instagram, YouTube, and X already cover
the sites that matter. Revisit when a site needs a scriptlet a hand-written
script cannot cover.

**Apache-2.0 surrogates, worth knowing about elsewhere.**
<https://github.com/duckduckgo/tracker-surrogates> is Apache-2.0 and ships 19
redirect surrogates: `ga.js`, `gpt.js`, `adsbygoogle.js`, `google-ima.js`,
`amzn_apstag.js`, `criteo.js`, `outbrain.js`, `noop.js` and others. These are
redirect resources rather than scriptlets, so they do nothing for the gap
above. They are directly relevant to `nook-stealth-redirects.js`, which
hand-maintains a stub table today. Out of scope for this phase; see
`docs/superpowers/specs/2026-09-16-stealth-redirects-design.md` when that work
resumes, and note the constraint recorded there that a stub must never be
served to a vendor that validates its payload.

**True procedural cosmetic filters.** `:has-text`, `:upward`, `:matches-css` are skipped. `:has()` is not affected, since WebKit supports it natively and those rules go through the content rule list. Revisit if the skip count logged by `nook-cosmetic.js` turns out to be large on real sites.

**iOS slices of the Rust library.** `build.sh` already carries commented instructions for `aarch64-apple-ios` and `aarch64-apple-ios-sim` and an XCFramework. That belongs to phase 3.

**Serialized cosmetic cache warm start.** The old engine reused a serialized `WebExtension` across launches. The new one rebuilds from rules. If the build time logged by `CosmeticFilterEngine` is over a second on a cold launch, add serialization; the crate supports it.

**Sharing one engine between cosmetics and request counting.** `RequestStatsEngine`
builds an `adblock::Engine` from the same rules, and `CosmeticFilterEngine` now
builds another. When detailed counts are on, that is two engines over one rule
set. They have different lifecycles today, which is why this plan leaves them
separate, but on a phone the duplicate is worth removing. Revisit during the
phase 3 memory spike.
