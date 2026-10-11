//! The real bundled lists plus the real resource files must yield a scriptlet
//! payload for youtube.com. Guards the whole chain offline.

use adblock::lists::{FilterSet, ParseOptions};
use adblock::resources::{PermissionMask, Resource};
use adblock::Engine;
use std::fs;
use std::path::Path;

fn res_dir() -> std::path::PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../../Packages/NookBlocker/Sources/NookBlocker/Resources")
        .canonicalize()
        .expect("resources dir")
}

const TRUSTED_LISTS: &[&str] = &[
    "ublock-filters.min", "ublock-privacy.min", "ublock-badware",
    "ublock-quick-fixes", "ublock-unbreak", "nook-filters-default",
];

fn engine() -> Engine {
    let dir = res_dir();
    let mut set = FilterSet::new(false);
    for entry in fs::read_dir(&dir).expect("readable") {
        let p = entry.unwrap().path();
        if p.extension().and_then(|e| e.to_str()) != Some("txt") { continue; }
        let stem = p.file_stem().unwrap().to_str().unwrap().to_string();
        let text = fs::read_to_string(&p).unwrap();
        let trusted = TRUSTED_LISTS.contains(&stem.as_str());
        set.add_filter_list(text, ParseOptions {
            permissions: if trusted { PermissionMask::from_bits(1) } else { PermissionMask::default() },
            ..ParseOptions::default()
        });
    }
    let mut engine = Engine::new_with_filter_set(set);

    // The manifest is exactly the JSON the app hands the engine, so deserializing
    // it straight into Resource also proves the Swift side needs no fix-up.
    let resources: Vec<Resource> =
        serde_json::from_str(&fs::read_to_string(dir.join("scriptlets.json")).unwrap())
            .expect("scriptlets.json must deserialize as adblock Resources");
    engine.use_resources(resources);
    engine
}

/// The real bundled lists plus the generated resource manifest must produce
/// uBlock Origin's actual YouTube ad stack. Guards the whole chain offline:
/// list parsing, trust permissions, resource lookup and dependency inlining.
#[test]
fn youtube_watch_page_gets_ubos_ad_stack() {
    let e = engine();
    let out = e.url_cosmetic_resources("https://www.youtube.com/watch?v=dQw4w9WgXcQ");
    for needle in [
        // The player response, which is what schedules the pre-roll.
        "jsonPruneFetchResponse(",
        "jsonPruneXhrResponse(",
        "trustedReplaceFetchResponse(",
        "trustedReplaceXhrResponse(",
        // The inline globals.
        "setConstant(\"ytInitialPlayerResponse.adPlacements\"",
    ] {
        assert!(out.injected_script.contains(needle), "no {needle} for a youtube watch page");
    }
    // uBO's request-level technique: it edited the player XHR until October 2026 and edits
    // what goes into JSON.stringify since. Either list vintage must resolve one of them.
    assert!(
        ["trustedJsonEditXhrRequest(", "trustedEditInboundObject("].iter().any(|n| out.injected_script.contains(n)),
        "no request-level edit for a youtube watch page"
    );
    // The preventFetch/preventXhr assertions that stood here went with the
    // nook-filters-default rules they checked: they faked a successful empty
    // response for ptracking and api/stats/ads, which is a detection surface for
    // nothing once the player response carries no ad.

    // A trusted rule resolving proves the permission bits survive the manifest.
    assert!(
        out.injected_script.matches("try {").count() > 20,
        "expected uBO's full stack, got {} invocations",
        out.injected_script.matches("try {").count()
    );
}

/// uBO's redirect resources double as argument-less scriptlets. They are whole
/// scripts rather than callable functions, so this guards that adblock-rust
/// still injects them and that the generator gave them a usable mime type.
#[test]
fn redirect_resources_inject_as_scriptlets() {
    let e = engine();
    let out = e.url_cosmetic_resources("https://spaste.com/");
    assert!(
        out.injected_script.contains("FuckAdBlock"),
        "nofab body missing; got {} bytes",
        out.injected_script.len()
    );
}

/// The app restores the engine from `Engine::serialize` bytes at launch instead
/// of parsing the lists again. Resources are not part of those bytes and are
/// installed again; everything else, trusted permissions included, has to come back.
#[test]
fn serialized_engine_answers_like_the_built_one() {
    let built = engine();
    let bytes = built.serialize();
    let mut restored = Engine::default();
    restored.deserialize(&bytes).expect("own bytes deserialize");
    let resources: Vec<Resource> =
        serde_json::from_str(&fs::read_to_string(res_dir().join("scriptlets.json")).unwrap()).unwrap();
    restored.use_resources(resources);

    for url in [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://www.cnn.com/",
        "https://www.facebook.com/",
        "https://www.reddit.com/r/swift/",
        "https://www.nytimes.com/",
        "https://spaste.com/",
        "https://example.com/",
    ] {
        let a = built.url_cosmetic_resources(url);
        let b = restored.url_cosmetic_resources(url);
        // adblock-rust emits scriptlets in hash order, new on every call, so compare the lines as a set.
        let lines = |script: &str| { let mut l: Vec<String> = script.lines().map(String::from).collect(); l.sort(); l };
        assert!(lines(&a.injected_script) == lines(&b.injected_script), "scriptlets differ for {url}");
        assert_eq!(a.hide_selectors, b.hide_selectors, "hide selectors differ for {url}");
        assert_eq!(a.procedural_actions, b.procedural_actions, "procedural filters differ for {url}");
        assert_eq!(a.exceptions, b.exceptions, "exceptions differ for {url}");
        assert_eq!(a.generichide, b.generichide, "generichide differs for {url}");
    }
    // A trusted-* scriptlet only resolves with the permission bit: it survived.
    assert!(restored
        .url_cosmetic_resources("https://www.youtube.com/watch?v=x")
        .injected_script
        .contains("trustedReplaceFetchResponse("));

    use adblock::request::Request;
    for (url, source, kind) in [
        ("https://securepubads.g.doubleclick.net/tag/js/gpt.js", "https://www.cnn.com/", "script"),
        ("https://cdn-media.brightline.tv/config/v3/1018.json", "https://www.cnn.com/", "xmlhttprequest"),
        ("https://t.co/abc", "https://x.com/home", "document"),
        ("https://www.cnn.com/index.css", "https://www.cnn.com/", "stylesheet"),
    ] {
        let request = Request::new(url, source, kind, "GET").unwrap();
        let (a, b) = (built.check_network_request(&request), restored.check_network_request(&request));
        assert_eq!(a.should_block(), b.should_block(), "network verdict differs for {url}");
        assert_eq!(a.redirect, b.redirect, "redirect differs for {url}");
    }
}
