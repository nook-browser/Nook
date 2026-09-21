//! C ABI over adblock::content_blocking: filter text to WKContentRuleList JSON.
//!
//! Replaces AdGuard's SafariConverterLib, which is GPL-3.0 and therefore cannot
//! carry Nook's section 7 App Store exception. This module is MPL-2.0, like the
//! crate it wraps.

use crate::guard;
use adblock::content_blocking::{CbRule, CbRuleEquivalent};
use adblock::filters::cosmetic::CosmeticFilterMask;
use adblock::lists::{parse_filter, ParseOptions, ParsedLine};
use std::convert::TryFrom;
use std::ffi::CString;
use std::os::raw::c_char;
use std::ptr;

/// Convert ABP/uBlock filter text into a JSON array of WKContentRuleList rules.
///
/// Writes the converted rule count to `*out_rule_count`, the count of lines
/// deliberately skipped because they cancel another rule to `*out_skipped_count`,
/// and the count of lines that could not be expressed in Safari's syntax to
/// `*out_unconverted_count`. Any of the three may be NULL.
///
/// "Unconverted" is not "lost": procedural cosmetic filters come back through
/// the cosmetic lookup at page load, and `$removeparam` is handled by
/// TrackingParamStripper. Calling that number an error rate is what made it
/// misleading.
///
/// Returns NULL on a null or non-UTF-8 input. Free with nook_adblock_string_free.
#[no_mangle]
pub unsafe extern "C" fn nook_adblock_convert_to_content_blocking(
    rules_utf8: *const c_char,
    rules_len: usize,
    out_rule_count: *mut usize,
    out_skipped_count: *mut usize,
    out_unconverted_count: *mut usize,
) -> *mut c_char {
    if rules_utf8.is_null() {
        return ptr::null_mut();
    }
    let bytes = std::slice::from_raw_parts(rules_utf8 as *const u8, rules_len);
    let Ok(text) = std::str::from_utf8(bytes) else {
        return ptr::null_mut();
    };
    let stats = guard(|| convert_text(text), Conversion::default());
    let Ok(json) = serde_json::to_string(&stats.rules) else {
        return ptr::null_mut();
    };
    if !out_rule_count.is_null() {
        *out_rule_count = stats.rules.len();
    }
    if !out_skipped_count.is_null() {
        *out_skipped_count = stats.skipped;
    }
    if !out_unconverted_count.is_null() {
        *out_unconverted_count = stats.unconverted;
    }
    match CString::new(json) {
        Ok(c) => c.into_raw(),
        Err(_) => ptr::null_mut(),
    }
}

/// Free a string returned by any char*-returning function in this library.
/// NULL is a no-op.
#[no_mangle]
pub unsafe extern "C" fn nook_adblock_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// True for rules that cancel another rule rather than describing one.
///
/// Neither kind can be expressed as a standalone content blocking rule, and
/// handing either to the converter produces something actively wrong:
///
/// - A cosmetic exception (`#@#`) is inverted by the crate into
///   `unless_domain`, so `redtube.com#@#svg` becomes "hide every svg on the web
///   except on redtube.com". Left in, ~6,600 of these hid icons across every
///   site. Cosmetic exceptions belong to the lookup engine, which applies them
///   correctly per URL, and WebKit could not honour them here anyway: an
///   exception in one compiled list cannot override a rule in another.
/// - `$badfilter` cancels a network rule elsewhere in the lists. The crate
///   debug_asserts that it never arrives, and converting one turns a
///   cancellation into a block.
fn cancels_another_rule(parsed: &ParsedLine) -> bool {
    match parsed {
        ParsedLine::Cosmetic(c) => c.mask.contains(CosmeticFilterMask::UNHIDE),
        ParsedLine::Network(n) => n.is_badfilter(),
    }
}

/// WebKit matches `if-domain`/`unless-domain` exactly unless the entry starts with `*`.
/// The crate prefixes network rule domains but not cosmetic ones.
fn widen_domains_to_subdomains(rule: &mut CbRule) {
    for list in [&mut rule.trigger.if_domain, &mut rule.trigger.unless_domain] {
        let Some(domains) = list else { continue };
        for domain in domains.iter_mut() {
            if !domain.starts_with('*') {
                domain.insert(0, '*');
            }
        }
    }
}

#[derive(Default)]
pub(crate) struct Conversion {
    pub rules: Vec<CbRule>,
    /// Lines skipped on purpose because they cancel another rule.
    pub skipped: usize,
    /// Lines with no equivalent in Safari's content blocking syntax. Procedural
    /// cosmetic filters and `$redirect` dominate this; they are handled
    /// elsewhere rather than lost.
    pub unconverted: usize,
}

/// Convert filter text, counting deliberate skips apart from real failures.
///
/// `TryFrom<ParsedLine>` covers both network and cosmetic filters, so there is
/// no need to match on the variant beyond the cancellation check. A network
/// filter can yield more than one content blocking rule, which is what
/// CbRuleEquivalent's iterator is for.
fn convert_text(text: &str) -> Conversion {
    let opts = ParseOptions::default();
    let mut c = Conversion::default();

    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('!') || line.starts_with("[Adblock") {
            continue;
        }
        match parse_filter(line, true, opts) {
            Ok(parsed) => {
                if cancels_another_rule(&parsed) {
                    c.skipped += 1;
                    continue;
                }
                match CbRuleEquivalent::try_from(parsed) {
                    Ok(equivalent) => c.rules.extend(equivalent.into_iter().map(|mut r| {
                        widen_domains_to_subdomains(&mut r);
                        r
                    })),
                    Err(_) => c.unconverted += 1,
                }
            }
            Err(_) => c.unconverted += 1,
        }
    }
    c
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;
    use std::ffi::CStr;

    fn convert(text: &str) -> Vec<Value> {
        let c = convert_text(text);
        serde_json::from_str(&serde_json::to_string(&c.rules).unwrap()).unwrap()
    }

    #[test]
    fn network_block_rule_converts() {
        let out = convert("||ads.example.com^");
        assert_eq!(out.len(), 1);
        assert_eq!(out[0]["action"]["type"], "block");
        assert!(out[0]["trigger"]["url-filter"]
            .as_str()
            .unwrap()
            .contains("ads"));
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

    /// WebKit needs the `*` prefix or the rule only fires on the bare apex, so
    /// reddit.com##... never applied on www.reddit.com.
    #[test]
    fn cosmetic_domains_cover_subdomains() {
        let out = convert("reddit.com##shreddit-ad-post");
        assert_eq!(out[0]["trigger"]["if-domain"][0], "*reddit.com");

        let out = convert("~old.reddit.com##.x");
        assert_eq!(out[0]["trigger"]["unless-domain"][0], "*old.reddit.com");
    }

    /// Network rules already arrive prefixed; widening must not double it.
    #[test]
    fn network_domains_are_not_double_prefixed() {
        let out = convert("||ads.example.com^$domain=reddit.com");
        assert_eq!(out[0]["trigger"]["if-domain"][0], "*reddit.com");
    }

    #[test]
    fn comments_and_blank_lines_are_skipped_not_counted_as_errors() {
        let c = convert_text("! a comment\n\n[Adblock Plus 2.0]\n||x.test^\n");
        assert_eq!(c.rules.len(), 1);
        assert_eq!(c.unconverted, 0);
    }

    /// A rule the converter cannot express in Safari's syntax must be counted
    /// rather than silently dropped, so the Swift side can log a real error rate.
    #[test]
    fn unconvertible_lines_are_counted() {
        let c = convert_text("||x.test^$redirect=noopjs\n");
        assert!(c.unconverted >= 1, "expected at least one unconvertible line");
    }

    /// A single network filter can expand to more than one content blocking
    /// rule; the iterator must not drop the extras.
    #[test]
    fn multiple_rule_expansion_is_preserved() {
        let c = convert_text("||example.com^$third-party\n||other.test^\n");
        assert!(c.rules.len() >= 2);
    }

    /// `#@#` is a cosmetic EXCEPTION: it cancels a hide rule. It cannot be
    /// expressed as a standalone content blocking rule, and the crate inverts it
    /// into "hide everywhere EXCEPT here", which hides the element across the
    /// entire web. Every such rule must be skipped.
    #[test]
    fn cosmetic_exception_produces_no_rule() {
        let c = convert_text("redtube.com#@#svg\n");
        assert!(
            c.rules.is_empty(),
            "a cosmetic exception must not convert, got {}",
            serde_json::to_string(&c.rules).unwrap()
        );
        assert_eq!(c.skipped, 1);
    }

    /// The regression that hid all 46 SVGs on facebook.com.
    #[test]
    fn cosmetic_exception_never_becomes_a_global_hide() {
        let c = convert_text("redtube.com#@#svg\nexample.com##.ad\n");
        for r in &c.rules {
            let sel = r.action.selector.as_deref().unwrap_or("");
            assert_ne!(sel, "svg", "a bare svg hide rule escaped the converter");
            if sel == ".ad" {
                assert!(
                    r.trigger.if_domain.is_some(),
                    "the surviving hide rule lost its domain scoping"
                );
            }
        }
    }

    /// `$badfilter` cancels another network rule. The crate debug_asserts that
    /// these never reach the converter, and converting one turns a cancellation
    /// into a block.
    #[test]
    fn badfilter_rules_are_skipped() {
        let c = convert_text("||example.com^$badfilter\n");
        assert!(c.rules.is_empty(), "a $badfilter rule must not convert");
        assert_eq!(c.skipped, 1);
    }

    /// Skipping a rule that is deliberately unconvertible is not a failure, or
    /// the reported rate stops meaning anything.
    #[test]
    fn deliberate_skips_are_counted_apart_from_failures() {
        let c = convert_text("redtube.com#@#svg\n||example.com^$badfilter\n");
        assert_eq!(c.unconverted, 0);
        assert_eq!(c.skipped, 2);
    }

    #[test]
    fn ffi_roundtrip_and_free() {
        let text = "||ads.example.com^\n";
        let mut count = 0usize;
        let mut skipped = 0usize;
        let mut unconv = 0usize;
        unsafe {
            let p = nook_adblock_convert_to_content_blocking(
                text.as_ptr() as *const c_char,
                text.len(),
                &mut count,
                &mut skipped,
                &mut unconv,
            );
            assert!(!p.is_null());
            let json = CStr::from_ptr(p).to_str().unwrap().to_owned();
            assert!(json.starts_with('['));
            assert_eq!(count, 1);
            assert_eq!(skipped, 0);
            assert_eq!(unconv, 0);
            nook_adblock_string_free(p);
            nook_adblock_string_free(ptr::null_mut());

            assert!(nook_adblock_convert_to_content_blocking(
                ptr::null(),
                0,
                ptr::null_mut(),
                ptr::null_mut(),
                ptr::null_mut()
            )
            .is_null());
        }
    }

    /// Null count pointers are legal; the caller may not want the statistics.
    #[test]
    fn null_out_params_are_safe() {
        let text = "||ads.example.com^\n";
        unsafe {
            let p = nook_adblock_convert_to_content_blocking(
                text.as_ptr() as *const c_char,
                text.len(),
                ptr::null_mut(),
                ptr::null_mut(),
                ptr::null_mut(),
            );
            assert!(!p.is_null());
            nook_adblock_string_free(p);
        }
    }
}
