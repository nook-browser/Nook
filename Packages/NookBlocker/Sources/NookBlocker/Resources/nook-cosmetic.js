// Nook Content Blocker
//
// Applies cosmetic filter rules from adblock-rust (MPL-2.0). Runs in the page
// world at document start, in every frame.
//
// Main frame: window.__nookCosmeticConfig is set synchronously by a config user
// script injected before this one, so there is no round trip. Subframes ask the
// nookAdvancedBlocking message handler.
//
// Scope: plain hide selectors, plus procedural filters expressible as CSS.
// True procedural operators (:has-text, :upward, :matches-css) are skipped;
// they need a JS evaluator this build does not ship. Scriptlets are not
// executed, because the engine is given no scriptlet resources.
//
// Most cosmetic filtering does not reach this script at all: the converter
// turns plain cosmetic rules into css-display-none entries in the compiled
// WKContentRuleList, and WebKit applies those itself.
//
// Must never throw into the page.

(function () {
  if (window.__nookCosmeticLoaded) return;
  window.__nookCosmeticLoaded = true;

  var verbose = window.__nookCosmeticVerbose === true;

  function log() {
    if (!verbose) return;
    try {
      console.log.apply(console, ['[Nook AdBlock]'].concat([].slice.call(arguments)));
    } catch (e) {}
  }

  // A procedural filter is CSS-expressible when every selector operator is a
  // plain CSS selector. Anything else needs an evaluator we do not ship.
  // Shape comes from adblock-rust's ProceduralOrActionFilter, serialised by
  // serde with external tagging: {"selector":[{"CssSelector":"..."}],"action":{"Style":"..."}}
  function proceduralToCss(filter) {
    if (!filter || !Array.isArray(filter.selector)) return null;
    var parts = [];
    for (var i = 0; i < filter.selector.length; i++) {
      var op = filter.selector[i];
      if (!op || typeof op.CssSelector !== 'string') return null;
      parts.push(op.CssSelector);
    }
    if (!parts.length) return null;
    var selector = parts.join('');
    var action = filter.action;
    if (!action) return selector + '{display:none !important;}';
    if (typeof action.Style === 'string') return selector + '{' + action.Style + '}';
    // Remove and RemoveAttr and the rest need DOM work, not CSS.
    return null;
  }

  function buildCss(config) {
    var chunks = [];
    var hide = config && config.css;
    if (Array.isArray(hide) && hide.length) {
      chunks.push(hide.join(',\n') + '{display:none !important;}');
    }
    var procedural = config && config.extendedCss;
    if (Array.isArray(procedural)) {
      var skipped = 0;
      for (var i = 0; i < procedural.length; i++) {
        var css = proceduralToCss(procedural[i]);
        if (css) chunks.push(css);
        else skipped++;
      }
      if (skipped) log('skipped', skipped, 'procedural filter(s) needing a JS evaluator');
    }
    return chunks.join('\n');
  }

  function inject(css) {
    if (!css) return;
    try {
      var style = document.createElement('style');
      style.setAttribute('type', 'text/css');
      style.textContent = css;
      var parent = document.head || document.documentElement;
      if (parent) {
        parent.appendChild(style);
        return;
      }
      // documentElement can still be null at document start in a frame that has
      // not parsed its root element yet. Retry once the DOM exists.
      document.addEventListener('DOMContentLoaded', function () {
        try {
          (document.head || document.documentElement).appendChild(style);
        } catch (e) {}
      }, { once: true });
    } catch (e) {
      log('failed to inject stylesheet', e);
    }
  }

  function apply(config) {
    if (!config) return;
    inject(buildCss(config));
  }

  try {
    if (typeof window.__nookCosmeticConfig !== 'undefined') {
      apply(window.__nookCosmeticConfig);
      return;
    }
    var handler =
      window.webkit &&
      window.webkit.messageHandlers &&
      window.webkit.messageHandlers.nookAdvancedBlocking;
    if (!handler) return;
    handler
      .postMessage({ url: location.href })
      .then(apply)
      .catch(function (e) {
        log('subframe lookup failed', e);
      });
  } catch (e) {
    log('startup failed', e);
  }
})();
