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
    "ublock-filters", "ublock-privacy", "ublock-badware",
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
        // The inline globals, and uBO's current request-level technique.
        "setConstant(\"ytInitialPlayerResponse.adPlacements\"",
        "trustedJsonEditXhrRequest(",
        // Our own nook-filters-default rules, dead until the bodies existed.
        "preventFetch(",
        "preventXhr(",
    ] {
        assert!(out.injected_script.contains(needle), "no {needle} for a youtube watch page");
    }
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
