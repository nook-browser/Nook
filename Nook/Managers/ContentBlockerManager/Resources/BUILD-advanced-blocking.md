# Rebuilding nook-advanced-blocking.js

Generated from `@adguard/safari-extension` 4.3.0 (pulls `@adguard/extended-css` 2.1.1 and `@adguard/scriptlets` 2.3.1) plus the glue below. Built with esbuild 0.24.2 on Node 22. Only the output and this file are checked in.

1. `mkdir /tmp/nook-ab && cd /tmp/nook-ab && npm init -y && npm i @adguard/safari-extension@4.3.0`
2. `printf 'export default {};\n' > stub-polyfill.js` (the library top-level-imports `webextension-polyfill` for the unused `BackgroundScript`; the alias lets esbuild tree-shake it)
3. Save the glue below as `glue.js` and the header comment from the top of `nook-advanced-blocking.js` as `header.txt`.
4. `npx -y esbuild@0.24.2 glue.js --bundle --format=iife --platform=browser --target=safari17 --minify --legal-comments=none --alias:webextension-polyfill=./stub-polyfill.js --outfile=bundle.js`
5. `cat header.txt bundle.js > <repo>/Nook/Managers/ContentBlockerManager/Resources/nook-advanced-blocking.js && node --check` that file.

Why scriptlets bypass `ContentScript.runScriptlets`: the library stringifies each scriptlet and injects it as a `<script>` element (textContent, then blob: fallback). Strict `script-src` CSPs (x.com, facebook.com, github.com) block both, and those are the sites scriptlet rules target most. This file already runs in the page world as a WKUserScript, so the glue resolves each `{name, args}` with `scriptlets.getScriptletFunction(name)` (the public `scriptlets` export of `@adguard/scriptlets`; its map already includes every alias such as `ubo-set-constant.js`) and calls `fn(source, args)` directly. Every scriptlet in 2.x is compiled self-contained (helpers like `hit`, `toRegExp` inlined in the body), so no eval, `Function()`, or DOM insertion is needed and CSP cannot interfere. `js` rules still use the library's `<script>` path and remain subject to CSP. Smoke test (jsdom): `set-constant`, `ubo-set-constant.js`, `prevent-fetch` take effect with zero `<script>` elements created; a `js` rule still executes.

Glue (`glue.js`), verbatim:

```js
// Nook glue: obtains an AdGuard advanced-rules Configuration and applies it
// with @adguard/safari-extension. Runs as a WKUserScript (page world, all
// frames, document start). Must never throw into the page.
//
// Scriptlets are NOT run through ContentScript.runScriptlets: that path
// stringifies the scriptlet and injects a <script> element, which strict
// script-src CSPs (x.com, facebook.com, github.com) block. Since this user
// script already executes in the page world, we call the scriptlet functions
// directly. @adguard/scriptlets 2.x compiles every scriptlet as a
// self-contained function (helpers inlined in the body), so no eval, no
// Function(), no DOM insertion, and CSP cannot interfere.
import {
  ContentScript,
  ConsoleLogger,
  LoggingLevel,
  setLogger,
  setupDelayedEventDispatcher,
} from '@adguard/safari-extension';
import { scriptlets } from '@adguard/scriptlets';

const ENGINE = 'safari-extension'; // same value @adguard/safari-extension passes to scriptlets.invoke
const LIB_VERSION = '4.3.0';

(function main() {
  try {
    if (window.__nookAdvancedBlockingLoaded) return;
    window.__nookAdvancedBlockingLoaded = true;

    const verbose = window.__nookAdvancedBlockingVerbose === true;
    if (verbose) setLogger(new ConsoleLogger('[Nook AdBlock]', LoggingLevel.Debug));

    const runScriptlets = (list) => {
      if (!Array.isArray(list)) return;
      for (const s of list) {
        try {
          // scriptletsMap already contains every alias ("set-constant",
          // "set-constant.js", "ubo-set-constant", "ubo-set-constant.js", ...).
          const fn = s && typeof s.name === 'string' && scriptlets.getScriptletFunction(s.name);
          if (typeof fn !== 'function') {
            if (verbose) console.warn('[Nook AdBlock] unknown scriptlet', s && s.name);
            continue;
          }
          const args = Array.isArray(s.args) ? s.args : [];
          const source = { engine: ENGINE, name: s.name, args, version: LIB_VERSION, verbose };
          fn(source, args);
        } catch (e) {
          if (verbose) console.error('[Nook AdBlock] scriptlet failed', s && s.name, e);
        }
      }
    };

    const apply = (config) => {
      if (!config || typeof config !== 'object') return;
      const cs = new ContentScript();
      cs.insertCss(config.css);
      cs.insertExtendedCss(config.extendedCss);
      runScriptlets(config.scriptlets);
      cs.runScripts(config.js); // still a <script> element; blocked by strict CSP, same as AdGuard's own app-extension path
    };

    // Fast path: Nook embedded the configuration in a preceding user script.
    const embedded = window.__nookAdvancedBlockingConfig;
    if (embedded !== undefined) {
      try { delete window.__nookAdvancedBlockingConfig; } catch (_) { /* ignore */ }
      apply(embedded);
      return;
    }

    const handler = window.webkit && window.webkit.messageHandlers
      && window.webkit.messageHandlers.nookAdvancedBlocking;
    if (!handler) return;

    // Hold DOMContentLoaded/load (max 1000ms) until rules are applied, same as
    // AdGuard's Safari App Extension sample.
    const dispatchDelayedEvents = setupDelayedEventDispatcher(1000);

    let topUrl = null;
    if (window.top !== window) {
      try { topUrl = window.top.location.href; } catch (_) { topUrl = document.referrer || null; }
    }
    let url = location.href;
    // about:blank / data: / srcdoc frames created by JS: use the top URL.
    if (!url.startsWith('http') && topUrl) url = topUrl;

    Promise.resolve(handler.postMessage({ url, topUrl }))
      .then(apply)
      .catch((e) => { if (verbose) console.error('[Nook AdBlock] config request failed', e); })
      .then(dispatchDelayedEvents);
  } catch (e) {
    if (window.__nookAdvancedBlockingVerbose === true) console.error('[Nook AdBlock] failed', e);
  }
})();
```
