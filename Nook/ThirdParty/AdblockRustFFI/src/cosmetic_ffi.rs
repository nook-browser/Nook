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
//! out.

use crate::guard;
use adblock::filters::cosmetic::CosmeticFilterMask;
use adblock::lists::{parse_filter, ParseOptions, ParsedLine};
use adblock::{Engine, FilterSet};
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

/// True for a plain hide rule a content rule list cannot scope to all of its sites: it names
/// an entity (`google.*`), or hostnames beside excluded ones. The rule list has no form for
/// either, so those sites would go without the rule.
fn needs_site_lookup(line: &str) -> bool {
    let Ok(ParsedLine::Cosmetic(c)) = parse_filter(line, true, ParseOptions::default()) else {
        return false;
    };
    let hides = !c.mask.intersects(CosmeticFilterMask::UNHIDE | CosmeticFilterMask::SCRIPT_INJECT)
        && c.action.is_none()
        && c.plain_css_selector().is_some();
    // With no site the engine can match, only exclusions are left and the rule would hide everywhere.
    let has_site = c.entities.is_some() || c.hostnames.is_some();
    hides && has_site && (c.entities.is_some() || c.not_entities.is_some() || c.not_hostnames.is_some())
}

/// The lines `nook_adblock_site_hide_engine` keeps. Lines are tested as text first: parsing
/// every line of every list costs a launch a few hundred milliseconds.
fn site_hide_lines(text: &str) -> Vec<&str> {
    text.lines()
        .map(str::trim)
        .filter(|line| {
            if line.starts_with('!') {
                return false;
            }
            let Some(sharp) = line.find('#') else { return false };
            let (sites, rest) = line.split_at(sharp);
            if rest.starts_with("#@#") {
                return !rest.starts_with("#@#+js(");
            }
            rest.starts_with("##")
                && !rest.starts_with("##+js(")
                && (sites.contains(".*") || sites.contains('~'))
                && needs_site_lookup(line)
        })
        .collect()
}

/// An engine of only the hide rules the content rule list cannot scope to their sites, plus
/// every cosmetic exception. Returns NULL on a null or non-UTF-8 input.
/// Free with nook_adblock_engine_free.
#[no_mangle]
pub unsafe extern "C" fn nook_adblock_site_hide_engine(
    rules_utf8: *const c_char,
    rules_len: usize,
) -> *mut Engine {
    if rules_utf8.is_null() {
        return ptr::null_mut();
    }
    let bytes = std::slice::from_raw_parts(rules_utf8 as *const u8, rules_len);
    let Ok(text) = std::str::from_utf8(bytes) else {
        return ptr::null_mut();
    };
    guard(
        || {
            let mut set = FilterSet::new(false);
            set.add_filter_list(site_hide_lines(text).join("\n"), ParseOptions::default());
            Box::into_raw(Box::new(Engine::new_with_filter_set(set)))
        },
        ptr::null_mut(),
    )
}

#[cfg(test)]
mod site_hide_tests {
    use super::*;
    use crate::content_blocking_ffi::nook_adblock_string_free;
    use crate::nook_adblock_engine_free;

    /// hide_selectors the site-hide engine built from `rules` returns for `url`.
    fn hides(rules: &str, url: &str) -> Vec<String> {
        let c = CString::new(url).unwrap();
        unsafe {
            let engine = nook_adblock_site_hide_engine(rules.as_ptr() as *const c_char, rules.len());
            assert!(!engine.is_null());
            let p = nook_adblock_cosmetic_for_url(engine, c.as_ptr());
            let out = if p.is_null() {
                Vec::new()
            } else {
                let v: serde_json::Value = serde_json::from_str(CStr::from_ptr(p).to_str().unwrap()).unwrap();
                nook_adblock_string_free(p);
                v["hide_selectors"].as_array().unwrap().iter().map(|s| s.as_str().unwrap().to_string()).collect()
            };
            nook_adblock_engine_free(engine);
            out
        }
    }

    #[test]
    fn entity_rule_applies_on_every_suffix_and_nowhere_else() {
        let rules = "google.*##.ad\n";
        assert_eq!(hides(rules, "https://www.google.co.uk/search?q=x"), [".ad"]);
        assert_eq!(hides(rules, "https://google.com/"), [".ad"]);
        assert!(hides(rules, "https://example.com/").is_empty());
    }

    /// The rule behind issue 430, applied where uBlock means it and only there.
    #[test]
    fn entity_rule_with_an_excluded_host() {
        let rules = "~vipbox.pl,vipbox.*,vipboxtv.*##.position-absolute\n";
        assert_eq!(hides(rules, "https://vipbox.lc/"), [".position-absolute"]);
        assert!(hides(rules, "https://vipbox.pl/").is_empty());
        assert!(hides(rules, "https://github.com/notifications").is_empty());
    }

    #[test]
    fn hostnames_beside_an_excluded_subdomain() {
        let rules = "wp.pl,~www.wp.pl##.x\n";
        assert_eq!(hides(rules, "https://poczta.wp.pl/"), [".x"]);
        assert!(hides(rules, "https://www.wp.pl/").is_empty());
    }

    #[test]
    fn exception_cancels_the_rule_on_its_site() {
        let rules = "google.*##.ad\ngoogle.de#@#.ad\n";
        assert_eq!(hides(rules, "https://www.google.fr/"), [".ad"]);
        assert!(hides(rules, "https://www.google.de/").is_empty());
    }

    /// What the rule list already covers, and what would hide everywhere, stays out.
    #[test]
    fn everything_else_is_left_out() {
        let rules = "example.com##.plain\n##.generic\n~x.com##.everywhere-but\n/re/,~x.com##.regex\n\
                     google.*##.a:has-text(x)\ngoogle.*##+js(nowoif)\ngoogle.*##.b:style(color: red)\n\
                     ||ads.example.com^\n! google.*##.commented\n";
        assert!(site_hide_lines(rules).is_empty(), "kept {:?}", site_hide_lines(rules));
        for url in ["https://example.com/", "https://www.google.com/", "https://x.com/", "https://y.test/"] {
            assert!(hides(rules, url).is_empty(), "{url}");
        }
    }

    /// The real lists: enough rules to be worth it, and quick enough to build at every launch.
    #[test]
    fn bundled_lists_build_quickly() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../../Packages/NookBlocker/Sources/NookBlocker/Resources");
        let mut text = String::new();
        for entry in std::fs::read_dir(dir).unwrap() {
            let p = entry.unwrap().path();
            if p.extension().and_then(|e| e.to_str()) == Some("txt") {
                text.push_str(&std::fs::read_to_string(&p).unwrap());
                text.push('\n');
            }
        }
        let start = std::time::Instant::now();
        let lines = site_hide_lines(&text);
        let rules = lines.iter().filter(|l| !l.contains("#@#")).count();
        unsafe {
            let engine = nook_adblock_site_hide_engine(text.as_ptr() as *const c_char, text.len());
            assert!(!engine.is_null());
            nook_adblock_engine_free(engine);
        }
        let took = start.elapsed();
        eprintln!("site-hide engine: {rules} rules, {} exceptions, {took:?} for both passes", lines.len() - rules);
        assert!(rules > 500, "only {rules} site-scoped hide rules found");
        assert!(took.as_millis() < 2000, "took {took:?}");
    }
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
