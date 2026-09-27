//! uBlock Origin's `urlskip=`: a navigation to a known redirector goes straight to the URL it
//! carries. adblock-rust does not parse the option, so each rule is split here. The filter
//! without it goes into a small debug engine, which reports the line that matched, and that
//! line's steps extract the destination. Steps follow uBO's `urlskip.js`.

use std::ffi::CString;
use std::os::raw::c_char;
use std::ptr;

use adblock::lists::ParseOptions;
use adblock::request::Request;
use adblock::{Engine, FilterSet};
use base64::alphabet;
use base64::engine::{DecodePaddingMode, GeneralPurpose, GeneralPurposeConfig};
use base64::Engine as _;
use percent_encoding::percent_decode_str;
use regex::Regex;
use url::Url;

use crate::{cstr, guard};

enum Step {
    /// `?name`: the value of query parameter `name`.
    Param(String),
    /// `/regex/`: the first capture group.
    Capture(Regex),
    /// `+https`: the current string with `https://` in front.
    Https,
    /// `-uricomponent`
    UriComponent,
    /// `-base64`, `-safebase64`
    Base64 { url_safe: bool },
    /// `-blocked`: in uBO, lets a strict-blocked page be skipped. Nook skips before the rule
    /// lists see the request, so it changes nothing here.
    Blocked,
}

struct Rule {
    steps: Vec<Step>,
    /// `to=` domains, `~` ones negated. adblock-rust 0.13 parses the option but never checks
    /// it, and a rule carrying it never matches, so it is taken out of the filter and checked here.
    to: Vec<(bool, String)>,
}

impl Rule {
    fn allows(&self, url: &str) -> bool {
        let Some(host) = Url::parse(url).ok().and_then(|u| u.host_str().map(str::to_lowercase)) else {
            return false;
        };
        let covers = |d: &String| host == *d || host.ends_with(&format!(".{d}"));
        let wanted = self.to.iter().filter(|(negated, _)| !negated).map(|(_, d)| d).collect::<Vec<_>>();
        (wanted.is_empty() || wanted.into_iter().any(covers))
            && !self.to.iter().any(|(negated, d)| *negated && covers(d))
    }
}

pub struct UrlSkipper {
    engine: Engine,
    /// By line of the engine's one list.
    rules: Vec<Rule>,
}

impl UrlSkipper {
    pub fn new(text: &str) -> Self {
        let (lines, rules): (Vec<String>, Vec<Rule>) = text.lines().filter_map(split_rule).unzip();
        let mut set = FilterSet::new(true);
        set.add_filter_list(lines.join("\n"), ParseOptions::default());
        UrlSkipper { engine: Engine::new_with_filter_set_no_optimize(set), rules }
    }

    pub fn rule_count(&self) -> usize {
        self.rules.len()
    }

    /// Where a document request for `url` from a page at `source` should go instead.
    pub fn target(&self, url: &str, source: &str) -> Option<String> {
        let request = Request::new(url, source, "document", "GET").ok()?;
        let line = self.engine.check_network_request(&request).filter?.source_location?.line_number;
        let rule = self.rules.get(line as usize).filter(|r| r.allows(url))?;
        apply(&rule.steps, url).filter(|target| target != url)
    }
}

/// `pattern$options,urlskip=steps,options` as the filter without `urlskip=`, typed as a
/// document, plus its steps. None when it is not a urlskip rule or a step is unknown.
fn split_rule(line: &str) -> Option<(String, Rule)> {
    let line = line.trim();
    if line.starts_with('!') || line.starts_with("@@") {
        return None;
    }
    let at = line.find("urlskip=")?;
    let dollar = line[..at].rfind('$')?;
    let mut options: Vec<&str> = line[dollar + 1..at].split(',').filter(|o| !o.is_empty()).collect();
    let mut steps = Vec::new();
    for token in line[at + "urlskip=".len()..].split(' ').filter(|t| !t.is_empty()) {
        // A regex step ends at its last slash, so a comma inside {0,2} stays in the regex.
        let regex_end = if token.starts_with('/') { token.rfind('/').filter(|&i| i > 0).map(|i| i + 1) } else { None };
        let from = regex_end.unwrap_or(0);
        let (step, rest) = match token[from..].find(',') {
            Some(i) => (&token[..from + i], Some(&token[from + i + 1..])),
            None => (token, None),
        };
        steps.push(parse_step(step)?);
        if let Some(rest) = rest {
            options.extend(rest.split(',').filter(|o| !o.is_empty()));
            break;
        }
    }
    if steps.is_empty() {
        return None;
    }
    let mut to = Vec::new();
    options.retain(|o| match o.strip_prefix("to=") {
        Some(domains) => {
            to.extend(domains.split('|').map(|d| match d.strip_prefix('~') {
                Some(d) => (true, d.to_lowercase()),
                None => (false, d.to_lowercase()),
            }));
            false
        }
        None => true,
    });
    if !options.iter().any(|o| *o == "doc" || *o == "document") {
        options.push("doc");
    }
    Some((format!("{}${}", &line[..dollar], options.join(",")), Rule { steps, to }))
}

fn parse_step(step: &str) -> Option<Step> {
    Some(match step {
        "+https" => Step::Https,
        "-uricomponent" => Step::UriComponent,
        "-base64" => Step::Base64 { url_safe: false },
        "-safebase64" => Step::Base64 { url_safe: true },
        "-blocked" => Step::Blocked,
        _ if step.len() > 1 && step.starts_with('?') => Step::Param(step[1..].to_string()),
        _ if step.len() > 2 && step.starts_with('/') && step.ends_with('/') => {
            Step::Capture(Regex::new(&step[1..step.len() - 1]).ok()?)
        }
        _ => return None,
    })
}

fn apply(steps: &[Step], url: &str) -> Option<String> {
    // atob() is forgiving about padding; so is this.
    let forgiving = GeneralPurposeConfig::new().with_decode_padding_mode(DecodePaddingMode::Indifferent);
    let mut current = url.to_string();
    for step in steps {
        current = match step {
            Step::Param(name) => Url::parse(&current)
                .ok()?
                .query_pairs()
                .find(|(k, _)| k == name)?
                .1
                .replace(' ', "%20"),
            Step::Capture(re) => re.captures(&current)?.get(1)?.as_str().to_string(),
            Step::Https => {
                let rest = current.strip_prefix("https://").or_else(|| current.strip_prefix("http://")).unwrap_or(current.as_str());
                if Regex::new(r"^[\w-]+://").ok()?.is_match(rest) {
                    return None;
                }
                format!("https://{rest}")
            }
            Step::UriComponent => percent_decode_str(&current).decode_utf8().ok()?.into_owned(),
            Step::Base64 { url_safe } => {
                let alphabet = if *url_safe { &alphabet::URL_SAFE } else { &alphabet::STANDARD };
                let bytes = GeneralPurpose::new(alphabet, forgiving).decode(current.trim()).ok()?;
                String::from_utf8(bytes).ok()?
            }
            Step::Blocked => current,
        };
    }
    let target = Url::parse(&current).ok()?;
    matches!(target.scheme(), "http" | "https").then_some(current)
}

/// Builds a skipper from filter list text. Only lines with `urlskip=` are read.
#[no_mangle]
pub unsafe extern "C" fn nook_adblock_urlskip_new(
    rules_utf8: *const c_char,
    rules_len: usize,
    out_rule_count: *mut usize,
) -> *mut UrlSkipper {
    if rules_utf8.is_null() {
        return ptr::null_mut();
    }
    let bytes = std::slice::from_raw_parts(rules_utf8 as *const u8, rules_len);
    let Ok(text) = std::str::from_utf8(bytes) else {
        return ptr::null_mut();
    };
    guard(
        || {
            let skipper = UrlSkipper::new(text);
            if !out_rule_count.is_null() {
                *out_rule_count = skipper.rule_count();
            }
            Box::into_raw(Box::new(skipper))
        },
        ptr::null_mut(),
    )
}

/// The URL a navigation to `url` from `source_url` should load instead, or NULL.
/// Free with `nook_adblock_string_free`.
#[no_mangle]
pub unsafe extern "C" fn nook_adblock_urlskip_target(
    skipper: *mut UrlSkipper,
    url: *const c_char,
    source_url: *const c_char,
) -> *mut c_char {
    if skipper.is_null() {
        return ptr::null_mut();
    }
    let (Some(url), Some(source)) = (cstr(url), cstr(source_url)) else {
        return ptr::null_mut();
    };
    let skipper = &*skipper;
    guard(
        || match skipper.target(url, source).map(CString::new) {
            Some(Ok(c)) => c.into_raw(),
            _ => ptr::null_mut(),
        },
        ptr::null_mut(),
    )
}

#[no_mangle]
pub unsafe extern "C" fn nook_adblock_urlskip_free(skipper: *mut UrlSkipper) {
    if !skipper.is_null() {
        drop(Box::from_raw(skipper));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn skip(rules: &str, url: &str) -> Option<String> {
        UrlSkipper::new(rules).target(url, url)
    }

    #[test]
    fn param_step() {
        let rules = "||go.redirectingat.com/*^url=http$doc,urlskip=?url\n";
        assert_eq!(
            skip(rules, "https://go.redirectingat.com/?id=1&url=https%3A%2F%2Fshop.example%2Fa%3Fb%3D1").as_deref(),
            Some("https://shop.example/a?b=1")
        );
        assert_eq!(skip(rules, "https://go.redirectingat.com/?id=1"), None);
        assert_eq!(skip(rules, "https://example.com/?url=https%3A%2F%2Fshop.example"), None);
    }

    #[test]
    fn regex_step_keeps_its_commas_and_options_after_it() {
        let rules = "||click.pstmrk.it^$doc,urlskip=/\\.pstmrk\\.it\\/[23][mst]{0,2}\\/([^\\/?#]+)/ -uricomponent +https\n";
        assert_eq!(
            skip(rules, "https://click.pstmrk.it/3s/shop.example%2Fitem/abc/def").as_deref(),
            Some("https://shop.example/item")
        );
        let (rule, parsed) = split_rule("||a.test/$urlskip=/x(y)/,doc,to=a.test|~b.a.test,1p").unwrap();
        assert_eq!(rule, "||a.test/$doc,1p");
        assert_eq!(parsed.steps.len(), 1);
        assert!(parsed.allows("https://c.a.test/") && !parsed.allows("https://b.a.test/"));
    }

    #[test]
    fn base64_steps() {
        // "https://shop.example/" in both alphabets, padding dropped.
        let rules = "||mail.test/click/$doc,urlskip=/\\/click\\/(aHR0c[^\\/]+)/ -base64\n\
                     ||bing.com/ck/a*u=a1$doc,urlskip=?u /^a1(.*)$/ -safebase64\n";
        assert_eq!(skip(rules, "https://mail.test/click/aHR0cHM6Ly9zaG9wLmV4YW1wbGUv").as_deref(), Some("https://shop.example/"));
        assert_eq!(skip(rules, "https://www.bing.com/ck/a?!&&p=1&u=a1aHR0cHM6Ly9zaG9wLmV4YW1wbGUv").as_deref(), Some("https://shop.example/"));
    }

    #[test]
    fn refuses_other_schemes_and_unknown_steps() {
        assert_eq!(skip("||r.test^$doc,urlskip=?u\n", "https://r.test/?u=javascript%3Aalert(1)"), None);
        assert_eq!(skip("||r.test^$doc,urlskip=?u &2\n", "https://r.test/?u=https%3A%2F%2Fa.test"), None);
    }

    /// Every bundled urlskip rule the engine can parse, and the Meta rules Nook adds.
    #[test]
    fn bundled_lists() {
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
        let skipper = UrlSkipper::new(&text);
        let total = text.lines().filter(|l| l.contains("urlskip=")).count();
        assert!(skipper.rule_count() * 10 >= total * 9, "{} of {} rules parsed", skipper.rule_count(), total);

        let cases = [
            ("https://l.threads.com/?u=https%3A%2F%2Fshop.example%2Fa&e=AT0", "https://shop.example/a"),
            ("https://l.facebook.com/l.php?u=https%3A%2F%2Fshop.example%2Fa%3Ffbclid%3D1&h=AT1", "https://shop.example/a?fbclid=1"),
            ("https://lm.facebook.com/l.php?u=https%3A%2F%2Fshop.example%2Fa&h=AT1", "https://shop.example/a"),
            ("https://l.instagram.com/?u=https%3A%2F%2Fshop.example%2Fa&e=AT2", "https://shop.example/a"),
            ("https://l.messenger.com/l.php?u=https%3A%2F%2Fshop.example%2Fa&h=AT3", "https://shop.example/a"),
        ];
        for (from, to) in cases {
            assert_eq!(skipper.target(from, from).as_deref(), Some(to), "{from}");
        }
        // A share dialog carries a URL but is not a redirect.
        let share = "https://www.facebook.com/sharer/sharer.php?u=https%3A%2F%2Fshop.example";
        assert_eq!(skipper.target(share, share), None);
    }
}
