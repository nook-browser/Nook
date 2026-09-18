//! Regression guard against converting Nook's real filter lists into rules that
//! hide far more than intended.
//!
//! Written after `redtube.com#@#svg`, a cosmetic *exception*, was converted into
//! a `css-display-none` rule for `svg` with no `if-domain`, which hid every icon
//! on every site. ~6,600 cosmetic exceptions were being inverted the same way.

use std::fs;
use std::path::Path;

/// Bare element selectors that would be catastrophic to hide site-wide.
const BARE_ELEMENTS: &[&str] = &[
    "svg", "img", "div", "span", "a", "p", "body", "html", "video", "audio", "canvas", "button",
    "input", "form", "table", "tr", "td", "li", "ul", "section", "article", "header", "footer",
    "main", "nav", "picture", "source", "figure", "iframe", "object", "embed",
];

fn bundled_filter_text() -> String {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../../Packages/NookBlocker/Sources/NookBlocker/Resources")
        .canonicalize()
        .expect("resources dir should exist");
    let mut text = String::new();
    for entry in fs::read_dir(&dir).expect("readable") {
        let p = entry.unwrap().path();
        if p.extension().and_then(|e| e.to_str()) == Some("txt") {
            if let Ok(s) = fs::read_to_string(&p) {
                text.push_str(&s);
                text.push('\n');
            }
        }
    }
    assert!(!text.is_empty(), "no filter lists found");
    text
}

/// Converts through the same path the app uses, including the skip for rules
/// that cancel other rules.
fn convert(text: &str) -> Vec<adblock::content_blocking::CbRule> {
    use adblock::content_blocking::CbRuleEquivalent;
    use adblock::filters::cosmetic::CosmeticFilterMask;
    use adblock::lists::{parse_filter, ParseOptions, ParsedLine};
    use std::convert::TryFrom;

    let opts = ParseOptions::default();
    let mut out = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('!') || line.starts_with("[Adblock") {
            continue;
        }
        let Ok(parsed) = parse_filter(line, true, opts) else {
            continue;
        };
        let cancels = match &parsed {
            ParsedLine::Cosmetic(c) => c.mask.contains(CosmeticFilterMask::UNHIDE),
            ParsedLine::Network(n) => n.is_badfilter(),
        };
        if cancels {
            continue;
        }
        if let Ok(equiv) = CbRuleEquivalent::try_from(parsed) {
            out.extend(equiv.into_iter());
        }
    }
    out
}

#[test]
fn no_rule_hides_a_bare_element_across_every_site() {
    let rules = convert(&bundled_filter_text());
    assert!(rules.len() > 10_000, "suspiciously few rules converted");

    let mut offenders = Vec::new();
    for rule in &rules {
        let Some(sel) = rule.action.selector.as_deref() else {
            continue;
        };
        if rule.trigger.if_domain.is_some() {
            continue;
        }
        for part in sel.split(',') {
            let part = part.trim();
            if BARE_ELEMENTS.contains(&part) {
                offenders.push(format!("{part} (from selector {sel})"));
            }
        }
    }
    assert!(
        offenders.is_empty(),
        "{} rule(s) hide a bare element with no domain restriction: {:?}",
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
