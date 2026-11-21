//! Regression guard against converting Nook's real filter lists into rules that
//! hide far more than intended.
//!
//! Written after `redtube.com#@#svg`, a cosmetic *exception*, was converted into
//! a `css-display-none` rule for `svg` with no `if-domain`, which hid every icon
//! on every site. ~6,600 cosmetic exceptions were being inverted the same way.
//!
//! The lists are whatever is in Resources: the bundled snapshots, or the live
//! lists after `scripts/refresh-filter-lists.sh`, which is how CI runs this daily.

use crate::content_blocking_ffi::convert_text;
use adblock::content_blocking::CbRule;
use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

/// Bare element selectors that would be catastrophic to hide site-wide.
const BARE_ELEMENTS: &[&str] = &[
    "svg", "img", "div", "span", "a", "p", "body", "html", "video", "audio", "canvas", "button",
    "input", "form", "table", "tr", "td", "li", "ul", "section", "article", "header", "footer",
    "main", "nav", "picture", "source", "figure", "iframe", "object", "embed",
];

/// Layout classes of Bootstrap, Tailwind and Primer. Hiding one on every site breaks pages,
/// not ads: `.position-absolute` took GitHub's notification buttons with it.
const UTILITY_CLASSES: &[&str] = &[
    ".position-absolute", ".position-relative", ".position-fixed", ".position-sticky", ".d-flex",
    ".d-none", ".d-block", ".d-inline", ".d-inline-block", ".d-grid", ".row", ".col", ".container",
    ".container-fluid", ".flex", ".hidden", ".block", ".inline", ".inline-block", ".grid",
    ".relative", ".absolute", ".fixed", ".sticky", ".w-100", ".h-100", ".w-full", ".h-full",
    ".btn", ".button", ".active", ".show", ".open", ".collapse", ".fade", ".modal", ".dropdown",
    ".nav", ".navbar", ".card", ".content", ".wrapper", ".main", ".header", ".footer", ".sidebar",
    ".clearfix", ".float-left", ".float-right", ".text-center", ".visible", ".invisible",
    ".overflow-hidden", ".sr-only",
];

fn resources() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../../Packages/NookBlocker/Sources/NookBlocker/Resources")
        .canonicalize()
        .expect("resources dir should exist")
}

/// Every list, minus the lines Nook removes at load (`nook-filter-removals.list`), as the app reads them.
fn bundled_filter_text() -> String {
    let removals = fs::read_to_string(resources().join("nook-filter-removals.list")).unwrap_or_default();
    let removed: HashSet<&str> = removals.lines().map(str::trim).filter(|l| !l.is_empty() && !l.starts_with('!')).collect();
    let mut text = String::new();
    for entry in fs::read_dir(resources()).expect("readable") {
        let p = entry.unwrap().path();
        if p.extension().and_then(|e| e.to_str()) == Some("txt") {
            if let Ok(s) = fs::read_to_string(&p) {
                for line in s.lines().filter(|l| !removed.contains(l.trim())) {
                    text.push_str(line);
                    text.push('\n');
                }
            }
        }
    }
    assert!(!text.is_empty(), "no filter lists found");
    text
}

/// The converter the app ships; a unit test because the crate builds no rlib for `tests/` to link.
fn convert(text: &str) -> Vec<CbRule> {
    convert_text(text).rules
}

/// Hide rules with no `if-domain` whose selector, or one part of it, is exactly one of `names`.
fn global_hides(rules: &[CbRule], names: &[&str]) -> Vec<String> {
    let mut offenders = Vec::new();
    for rule in rules {
        let Some(sel) = rule.action.selector.as_deref() else {
            continue;
        };
        if rule.trigger.if_domain.is_some() {
            continue;
        }
        for part in sel.split(',') {
            let part = part.trim();
            if names.contains(&part) {
                offenders.push(format!("{part} (from selector {sel})"));
            }
        }
    }
    offenders
}

#[test]
fn no_rule_hides_a_bare_element_across_every_site() {
    let rules = convert(&bundled_filter_text());
    assert!(rules.len() > 10_000, "suspiciously few rules converted");

    let offenders = global_hides(&rules, BARE_ELEMENTS);
    assert!(
        offenders.is_empty(),
        "{} rule(s) hide a bare element with no domain restriction: {:?}",
        offenders.len(),
        &offenders[..offenders.len().min(10)]
    );
}

/// When this fails on the live lists, find the list line behind the selector and add it to
/// `nook-filter-removals.list`: every installed copy drops it within hours, with no release.
#[test]
fn no_rule_hides_a_utility_class_across_every_site() {
    let offenders = global_hides(&convert(&bundled_filter_text()), UTILITY_CLASSES);
    assert!(
        offenders.is_empty(),
        "{} rule(s) hide a layout class on every site: {:?}",
        offenders.len(),
        &offenders[..offenders.len().min(10)]
    );
}

/// A cosmetic exception must never survive conversion. The crate turns one into
/// an `unless_domain` rule, which reads as "hide this everywhere else".
#[test]
fn cosmetic_exceptions_are_not_converted() {
    use adblock::content_blocking::CbType;

    let text = bundled_filter_text();
    let exceptions = text
        .lines()
        .filter(|l| {
            let l = l.trim();
            !l.starts_with('!') && l.contains("#@#")
        })
        .count();
    assert!(
        exceptions > 100,
        "expected the lists to contain cosmetic exceptions to guard against, found {exceptions}"
    );

    // Converting only the exceptions must produce nothing at all.
    let only_exceptions: String = text
        .lines()
        .filter(|l| {
            let l = l.trim();
            !l.starts_with('!') && l.contains("#@#")
        })
        .collect::<Vec<_>>()
        .join("\n");
    let rules = convert(&only_exceptions);
    let hides = rules
        .iter()
        .filter(|r| matches!(r.action.typ, CbType::CssDisplayNone))
        .count();
    assert_eq!(
        hides, 0,
        "{hides} cosmetic exception(s) were converted into hide rules"
    );
}
