//! Minimal C ABI over brave/adblock-rust for Nook.
//! Only answers "would this request be blocked?"; no cosmetic filtering.

use adblock::lists::ParseOptions;
use adblock::request::Request;
use adblock::{Engine, FilterSet};
use std::ffi::CStr;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;

pub(crate) mod content_blocking_ffi;

// panic = "abort" in release; catch_unwind still guards debug/test builds.
pub(crate) fn guard<T>(f: impl FnOnce() -> T, fallback: T) -> T {
    catch_unwind(AssertUnwindSafe(f)).unwrap_or(fallback)
}

unsafe fn cstr<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    CStr::from_ptr(p).to_str().ok()
}

#[no_mangle]
pub unsafe extern "C" fn nook_adblock_engine_from_rules(
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
            set.add_filter_list(text.to_owned(), ParseOptions::default());
            Box::into_raw(Box::new(Engine::new_with_filter_set(set)))
        },
        ptr::null_mut(),
    )
}

#[no_mangle]
pub unsafe extern "C" fn nook_adblock_engine_deserialize(bytes: *const u8, len: usize) -> *mut Engine {
    if bytes.is_null() {
        return ptr::null_mut();
    }
    let data = std::slice::from_raw_parts(bytes, len);
    guard(
        || {
            let mut engine = Engine::default();
            match engine.deserialize(data) {
                Ok(()) => Box::into_raw(Box::new(engine)),
                Err(_) => ptr::null_mut(),
            }
        },
        ptr::null_mut(),
    )
}

#[no_mangle]
pub unsafe extern "C" fn nook_adblock_engine_serialize(engine: *mut Engine, out_len: *mut usize) -> *mut u8 {
    if engine.is_null() || out_len.is_null() {
        return ptr::null_mut();
    }
    let engine = &*engine;
    guard(
        || {
            let mut v = engine.serialize().into_boxed_slice();
            *out_len = v.len();
            let p = v.as_mut_ptr();
            std::mem::forget(v);
            p
        },
        ptr::null_mut(),
    )
}

#[no_mangle]
pub unsafe extern "C" fn nook_adblock_buffer_free(bytes: *mut u8, len: usize) {
    if !bytes.is_null() {
        drop(Box::from_raw(std::slice::from_raw_parts_mut(bytes, len)));
    }
}

#[no_mangle]
pub unsafe extern "C" fn nook_adblock_engine_matches(
    engine: *mut Engine,
    url: *const c_char,
    source_url: *const c_char,
    request_type: *const c_char,
) -> bool {
    if engine.is_null() {
        return false;
    }
    let (Some(url), Some(source), Some(kind)) = (cstr(url), cstr(source_url), cstr(request_type)) else {
        return false;
    };
    let engine = &*engine;
    guard(
        || match Request::new(url, source, kind, "GET") {
            Ok(req) => engine.check_network_request(&req).should_block(),
            Err(_) => false,
        },
        false,
    )
}

#[no_mangle]
pub unsafe extern "C" fn nook_adblock_engine_free(engine: *mut Engine) {
    if !engine.is_null() {
        drop(Box::from_raw(engine));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    fn c(s: &str) -> CString {
        CString::new(s).unwrap()
    }

    #[test]
    fn ffi_smoke() {
        let rules = "||example.com^\n@@||example.com/allowed.js\n";
        let site = c("https://site.test/");
        let script = c("script");
        unsafe {
            let e = nook_adblock_engine_from_rules(rules.as_ptr() as *const c_char, rules.len());
            assert!(!e.is_null());
            assert!(nook_adblock_engine_matches(e, c("https://example.com/ad.js").as_ptr(), site.as_ptr(), script.as_ptr()));
            assert!(!nook_adblock_engine_matches(e, c("https://other.test/x.js").as_ptr(), site.as_ptr(), script.as_ptr()));
            assert!(!nook_adblock_engine_matches(e, c("https://example.com/allowed.js").as_ptr(), site.as_ptr(), script.as_ptr()));
            assert!(!nook_adblock_engine_matches(e, c("not a url").as_ptr(), site.as_ptr(), script.as_ptr()));
            assert!(!nook_adblock_engine_matches(e, ptr::null(), site.as_ptr(), script.as_ptr()));

            let mut len = 0usize;
            let buf = nook_adblock_engine_serialize(e, &mut len);
            assert!(!buf.is_null() && len > 0);
            let e2 = nook_adblock_engine_deserialize(buf, len);
            assert!(!e2.is_null());
            assert!(nook_adblock_engine_matches(e2, c("https://example.com/ad.js").as_ptr(), site.as_ptr(), script.as_ptr()));
            nook_adblock_buffer_free(buf, len);

            assert!(nook_adblock_engine_deserialize(b"garbage".as_ptr(), 7).is_null());
            assert!(!nook_adblock_engine_matches(ptr::null_mut(), site.as_ptr(), site.as_ptr(), script.as_ptr()));

            nook_adblock_engine_free(e2);
            nook_adblock_engine_free(e);
            nook_adblock_engine_free(ptr::null_mut());
        }
    }

    /// Reachability check for the `content-blocking` feature, which is off by
    /// default. Without it the module is invisible and every conversion call
    /// fails to compile with an unresolved-module error rather than a missing
    /// feature one.
    #[test]
    fn content_blocking_module_is_available() {
        use adblock::content_blocking::{CbRuleEquivalent, CbType};
        use adblock::lists::{parse_filter, ParseOptions};
        use std::convert::TryFrom;

        let parsed = parse_filter("||example.com^", true, ParseOptions::default())
            .expect("filter should parse");
        let equivalent = CbRuleEquivalent::try_from(parsed).expect("should convert");
        let rules: Vec<_> = equivalent.into_iter().collect();
        assert_eq!(rules.len(), 1);
        assert!(matches!(rules[0].action.typ, CbType::Block));
        assert!(rules[0].trigger.url_filter.contains("example"));
    }
}
