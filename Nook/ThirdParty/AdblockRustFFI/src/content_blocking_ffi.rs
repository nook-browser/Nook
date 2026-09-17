//! C ABI over adblock::content_blocking: filter text to WKContentRuleList JSON.
//!
//! Replaces AdGuard's SafariConverterLib, which is GPL-3.0 and therefore cannot
//! carry Nook's section 7 App Store exception. This module is MPL-2.0, like the
//! crate it wraps.

use crate::guard;
use adblock::content_blocking::{CbRule, CbRuleEquivalent};
use adblock::lists::{parse_filter, ParseOptions};
use std::convert::TryFrom;
use std::ffi::CString;
use std::os::raw::c_char;
use std::ptr;

/// Convert ABP/uBlock filter text into a JSON array of WKContentRuleList rules.
/// Writes the converted rule count to `*out_rule_count` and the count of lines
/// that failed to convert to `*out_error_count`; either may be NULL.
/// Returns NULL on a null or non-UTF-8 input. Free with nook_adblock_string_free.
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
    let (rules, errors) = guard(|| convert_text(text), (Vec::new(), 0));
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
}

/// Free a string returned by any char*-returning function in this library.
/// NULL is a no-op.
#[no_mangle]
pub unsafe extern "C" fn nook_adblock_string_free(s: *mut c_char) {
    if !s.is_null() {
        drop(CString::from_raw(s));
    }
}

/// Returns the converted rules and the number of lines that could not convert.
///
/// `TryFrom<ParsedLine>` covers both network and cosmetic filters, so there is
/// no need to match on the variant here. A network filter can yield more than
/// one content blocking rule, which is what CbRuleEquivalent's iterator is for.
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
            Ok(parsed) => match CbRuleEquivalent::try_from(parsed) {
                Ok(equivalent) => out.extend(equivalent.into_iter()),
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
    use std::ffi::CStr;

    fn convert(text: &str) -> Vec<Value> {
        let (rules, _) = convert_text(text);
        serde_json::from_str(&serde_json::to_string(&rules).unwrap()).unwrap()
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

    #[test]
    fn comments_and_blank_lines_are_skipped_not_counted_as_errors() {
        let (rules, errors) = convert_text("! a comment\n\n[Adblock Plus 2.0]\n||x.test^\n");
        assert_eq!(rules.len(), 1);
        assert_eq!(errors, 0);
    }

    /// A rule the converter cannot express in Safari's syntax must be counted
    /// rather than silently dropped, so the Swift side can log a real error rate.
    #[test]
    fn unconvertible_lines_are_counted() {
        let (_, errors) = convert_text("||x.test^$redirect=noopjs\n");
        assert!(errors >= 1, "expected at least one unconvertible line");
    }

    /// A single network filter can expand to more than one content blocking
    /// rule; the iterator must not drop the extras.
    #[test]
    fn multiple_rule_expansion_is_preserved() {
        let (rules, _) = convert_text("||example.com^$third-party\n||other.test^\n");
        assert!(rules.len() >= 2);
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
            let json = CStr::from_ptr(p).to_str().unwrap().to_owned();
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
            );
            assert!(!p.is_null());
            nook_adblock_string_free(p);
        }
    }
}
