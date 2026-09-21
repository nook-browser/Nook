//! Minimal C ABI over brave/adblock-rust for Nook.
//! Only answers "would this request be blocked?"; no cosmetic filtering.

use adblock::lists::ParseOptions;
use adblock::resources::{PermissionMask, Resource};
use adblock::request::Request;
use adblock::{Engine, FilterSet};
use std::ffi::CStr;
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};
use std::ptr;

pub(crate) mod content_blocking_ffi;
pub(crate) mod cosmetic_ffi;

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

/// The one permission bit Nook grants. A list parsed with it may invoke
/// `trusted-*` scriptlets; a resource declaring it is refused to every other list.
pub(crate) const TRUSTED: u8 = 1;

#[derive(serde::Deserialize)]
struct ListInput {
    rules: String,
    #[serde(default)]
    trusted: bool,
}

/// Build an engine from a JSON array of `{ "rules": "...", "trusted": bool }`.
///
/// Per-list rather than one blob because `ParseOptions::permissions` is applied
/// at parse time, and it is what gates `trusted-*` scriptlets.
#[no_mangle]
pub unsafe extern "C" fn nook_adblock_engine_from_lists(
    json_utf8: *const c_char,
    json_len: usize,
) -> *mut Engine {
    if json_utf8.is_null() {
        return ptr::null_mut();
    }
    let bytes = std::slice::from_raw_parts(json_utf8 as *const u8, json_len);
    let Ok(text) = std::str::from_utf8(bytes) else {
        return ptr::null_mut();
    };
    guard(
        || {
            let Ok(lists) = serde_json::from_str::<Vec<ListInput>>(text) else {
                return ptr::null_mut();
            };
            let mut set = FilterSet::new(false);
            for list in lists {
                let permissions = if list.trusted {
                    PermissionMask::from_bits(TRUSTED)
                } else {
                    PermissionMask::default()
                };
                set.add_filter_list(
                    list.rules,
                    ParseOptions {
                        permissions,
                        ..ParseOptions::default()
                    },
                );
            }
            Box::into_raw(Box::new(Engine::new_with_filter_set(set)))
        },
        ptr::null_mut(),
    )
}

/// Install Nook's scriptlet resource set. JSON array of `adblock::resources::Resource`.
///
/// Top-level scriptlets must be `application/javascript`; `fn/javascript` is
/// dependency-only. Names must end in `.js`, since lookup appends the extension.
/// Returns false if the JSON does not parse.
#[no_mangle]
pub unsafe extern "C" fn nook_adblock_engine_use_resources(
    engine: *mut Engine,
    json_utf8: *const c_char,
    json_len: usize,
) -> bool {
    if engine.is_null() || json_utf8.is_null() {
        return false;
    }
    let bytes = std::slice::from_raw_parts(json_utf8 as *const u8, json_len);
    let Ok(text) = std::str::from_utf8(bytes) else {
        return false;
    };
    let engine = &mut *engine;
    guard(
        || match serde_json::from_str::<Vec<Resource>>(text) {
            Ok(resources) => {
                engine.use_resources(resources);
                true
            }
            Err(_) => false,
        },
        false,
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
            let e = engine_from_test_rules(rules);
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

/// Wraps a bare rules blob as the single untrusted list the new builder expects.
#[cfg(test)]
pub(crate) fn engine_from_test_rules(rules: &str) -> *mut Engine {
    let json = serde_json::json!([{ "rules": rules, "trusted": false }]).to_string();
    unsafe { nook_adblock_engine_from_lists(json.as_ptr() as *const c_char, json.len()) }
}

#[cfg(test)]
mod scriptlet_tests {
    use super::*;
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine as _;
    use std::ffi::{CStr, CString};

    fn resource(name: &str, body: &str, trusted: bool) -> String {
        format!(
            r#"{{"name":"{name}","aliases":[],"kind":{{"mime":"application/javascript"}},"content":"{}","dependencies":[],"permission":{}}}"#,
            STANDARD.encode(body),
            if trusted { TRUSTED } else { 0 }
        )
    }

    /// injected_script for `url`, or "" when nothing applies.
    fn injected(lists: &str, resources: &str, url: &str) -> String {
        unsafe {
            let l = CString::new(lists).unwrap();
            let engine = nook_adblock_engine_from_lists(l.as_ptr(), lists.len());
            assert!(!engine.is_null(), "engine build failed");
            let r = CString::new(resources).unwrap();
            assert!(nook_adblock_engine_use_resources(engine, r.as_ptr(), resources.len()));
            let u = CString::new(url).unwrap();
            let out = cosmetic_ffi::nook_adblock_cosmetic_for_url(engine, u.as_ptr());
            let text = if out.is_null() {
                String::new()
            } else {
                let s = CStr::from_ptr(out).to_string_lossy().into_owned();
                content_blocking_ffi::nook_adblock_string_free(out);
                s
            };
            nook_adblock_engine_free(engine);
            serde_json::from_str::<serde_json::Value>(&text)
                .map(|v| v["injected_script"].as_str().unwrap_or("").to_string())
                .unwrap_or_default()
        }
    }

    const BODY: &str = "function nookMark(a) { window.__m = a; }";

    #[test]
    fn plain_scriptlet_runs_from_any_list() {
        let lists = r#"[{"rules":"example.com##+js(mark, hello)","trusted":false}]"#;
        let res = format!("[{}]", resource("mark.js", BODY, false));
        let out = injected(lists, &res, "https://example.com/");
        assert!(out.contains(r#"nookMark("hello")"#), "got: {out}");
    }

    #[test]
    fn trusted_scriptlet_runs_from_a_trusted_list() {
        let lists = r#"[{"rules":"example.com##+js(trusted-mark, hello)","trusted":true}]"#;
        let res = format!("[{}]", resource("trusted-mark.js", BODY, true));
        let out = injected(lists, &res, "https://example.com/");
        assert!(out.contains(r#"nookMark("hello")"#), "got: {out}");
    }

    /// The point of the trust model: an untrusted list cannot reach a trusted body.
    #[test]
    fn trusted_scriptlet_is_refused_to_an_untrusted_list() {
        let lists = r#"[{"rules":"example.com##+js(trusted-mark, hello)","trusted":false}]"#;
        let res = format!("[{}]", resource("trusted-mark.js", BODY, true));
        let out = injected(lists, &res, "https://example.com/");
        assert!(!out.contains("nookMark"), "trusted body leaked: {out}");
    }

    #[test]
    fn unknown_scriptlet_name_injects_nothing() {
        let lists = r#"[{"rules":"example.com##+js(no-such-thing, x)","trusted":true}]"#;
        let res = format!("[{}]", resource("mark.js", BODY, false));
        assert_eq!(injected(lists, &res, "https://example.com/"), "");
    }

    /// Only `function name(...)` bodies receive their arguments. Arrow and
    /// `async function` forms fall back to inlining with no call and no args.
    #[test]
    fn only_function_declarations_receive_arguments() {
        let lists = r#"[{"rules":"example.com##+js(arrow, hello)","trusted":false}]"#;
        let arrow = "const nookArrow = (a) => { window.__m = a; };";
        let res = format!("[{}]", resource("arrow.js", arrow, false));
        let out = injected(lists, &res, "https://example.com/");
        assert!(
            !out.contains(r#"nookArrow("hello")"#),
            "crate gained arrow support: {out}"
        );
    }
}

