//! C ABI for per-URL cosmetic rule lookup.
//!
//! Replaces AdGuard's FilterEngine/WebExtension, which is GPL-3.0. This module
//! is MPL-2.0, like the crate it wraps.
//!
//! There is no separate cache type here. `Engine::url_cosmetic_resources` is
//! the crate's public cosmetic API (`CosmeticFilterCache` is `pub(crate)`), and
//! `nook_adblock_engine_from_lists` already builds an `Engine`. So the caller
//! builds one engine and uses it for both request matching and cosmetic lookup,
//! freeing it with `nook_adblock_engine_free` as before.
//!
//! Scope note: plain cosmetic filters already become `css-display-none` actions
//! during conversion (see content_blocking_ffi), so they arrive through the
//! compiled WKContentRuleList and are not looked up here. This path carries
//! what the content rule list cannot express, chiefly procedural filters.
//!
//! Scriptlets: `injected_script` is populated from the Nook-authored resource
//! set installed by `nook_adblock_engine_use_resources`. Borrowed bodies stay
//! out; see LICENSE-EXCEPTION.md.

use crate::guard;
use adblock::Engine;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;

/// Cosmetic resources for one URL, as a NUL-terminated UTF-8 JSON object with
/// keys hide_selectors, procedural_actions, injected_script, exceptions and
/// generichide. Returns NULL when nothing applies or on bad input.
///
/// `engine` must come from nook_adblock_engine_from_lists. As with request
/// matching, the caller must serialize all calls on a given engine.
///
/// Free the result with nook_adblock_string_free.
#[no_mangle]
pub unsafe extern "C" fn nook_adblock_cosmetic_for_url(
    engine: *mut Engine,
    url: *const c_char,
) -> *mut c_char {
    if engine.is_null() || url.is_null() {
        return ptr::null_mut();
    }
    let Ok(url) = CStr::from_ptr(url).to_str() else {
        return ptr::null_mut();
    };
    let engine = &*engine;
    guard(
        || {
            let res = engine.url_cosmetic_resources(url);
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::content_blocking_ffi::nook_adblock_string_free;
    use crate::{engine_from_test_rules, nook_adblock_engine_free};
    use serde_json::Value;

    // :has-text is a procedural operator, so it cannot become a content rule
    // list entry and must come back through this path.
    const RULES: &str = "example.com##.ad-banner\nexample.com##.promo:has-text(Sponsored)\n";

    fn lookup(rules: &str, url: &str) -> Option<Value> {
        let c = CString::new(url).unwrap();
        unsafe {
            let engine =
                engine_from_test_rules(rules);
            assert!(!engine.is_null());
            let p = nook_adblock_cosmetic_for_url(engine, c.as_ptr());
            let out = if p.is_null() {
                None
            } else {
                let s = CStr::from_ptr(p).to_str().unwrap().to_owned();
                nook_adblock_string_free(p);
                Some(serde_json::from_str(&s).unwrap())
            };
            nook_adblock_engine_free(engine);
            out
        }
    }

    fn hide_selectors(v: &Value) -> Vec<String> {
        v["hide_selectors"]
            .as_array()
            .map(|a| {
                a.iter()
                    .filter_map(|s| s.as_str().map(String::from))
                    .collect()
            })
            .unwrap_or_default()
    }

    #[test]
    fn hostname_rule_applies_to_its_host() {
        let v = lookup(RULES, "https://example.com/page").expect("should match");
        assert!(hide_selectors(&v).contains(&".ad-banner".to_string()));
    }

    #[test]
    fn subdomain_inherits_the_hostname_rule() {
        let v = lookup(RULES, "https://www.example.com/page").expect("should match");
        assert!(hide_selectors(&v).contains(&".ad-banner".to_string()));
    }

    #[test]
    fn hostname_rule_does_not_leak_to_another_host() {
        // Either nothing applies at all, or whatever applies excludes .ad-banner.
        match lookup(RULES, "https://other.test/page") {
            None => {}
            Some(v) => assert!(!hide_selectors(&v).contains(&".ad-banner".to_string())),
        }
    }

    /// Procedural filters are the reason this lookup exists: they cannot be
    /// expressed as WKContentRuleList entries.
    #[test]
    fn procedural_filter_comes_back_as_json() {
        let v = lookup(RULES, "https://example.com/page").expect("should match");
        let procedural = v["procedural_actions"]
            .as_array()
            .cloned()
            .unwrap_or_default();
        assert!(
            !procedural.is_empty(),
            "a :has-text rule should arrive as a procedural action, got {v}"
        );
        let first = procedural[0]
            .as_str()
            .expect("procedural entries are JSON strings");
        let parsed: Value = serde_json::from_str(first).expect("should be valid JSON");
        assert!(parsed.get("selector").is_some(), "shape was {parsed}");
    }

    /// No scriptlet resources are given to the engine, so nothing should be
    /// injected even when a filter list asks for it.
    #[test]
    fn scriptlets_are_not_injected() {
        let rules = "example.com##+js(set-constant, foo, true)\n";
        if let Some(v) = lookup(rules, "https://example.com/page") {
            let script = v["injected_script"].as_str().unwrap_or("");
            assert!(script.is_empty(), "expected no scriptlet body, got {script}");
        }
    }

    #[test]
    fn no_rules_means_no_result() {
        assert!(lookup("", "https://example.com/").is_none());
    }

    #[test]
    fn null_inputs_are_safe() {
        unsafe {
            let c = CString::new("https://example.com/").unwrap();
            assert!(nook_adblock_cosmetic_for_url(ptr::null_mut(), c.as_ptr()).is_null());
            let engine =
                engine_from_test_rules(RULES);
            assert!(nook_adblock_cosmetic_for_url(engine, ptr::null()).is_null());
            nook_adblock_engine_free(engine);
        }
    }
}
