// Nook Content Blocker
// Stealth redirects: answer a known ad URL with the resource uBlock Origin's
// $redirect= rules name for it, instead of letting the content rule list fail
// it. A blocked request fails loudly (fetch rejects, XHR reports status 0,
// script/img fire error) and anti-adblock services read exactly those signals.
// A substituted body loads normally, and for the ad libraries whose rules name
// a real shim it also keeps pages working that would otherwise break on a
// missing googletag or google.ima.
//
// Covers requests JavaScript starts: fetch, XMLHttpRequest, and script/img
// elements built in code. It cannot cover a <script src> written in the page's
// own HTML: WebKit begins that load as the parser reaches the tag, before any
// observer could rewrite it. Those stay blocked and stay visible as errors.
//
// The table is per navigation and main frame only, set synchronously by
// AdvancedRulesEngine before this runs, because most $redirect rules are
// domain-scoped and a page needs only a handful. A subframe has no table and
// falls through to the rule lists, which still block. Everything not in the
// table is untouched and still blocked.
//
// Never answer a vendor that validates its payload. Ad-Shield compares the
// script it receives against an X-Length response header, and a data: URL has
// no headers, so an empty body reads as malformed and it escalates. The
// generator drops those rules; see scripts/build-redirects.mjs.
(function () {
  'use strict';

  if (window.__nookStealthRedirectsLoaded) return;
  window.__nookStealthRedirectsLoaded = true;

  // [regexSource, dataURL, [requestType, ...]]
  const TABLE = Array.isArray(window.__nookRedirects) ? window.__nookRedirects : [];
  if (TABLE.length === 0) return;

  const compiled = [];
  for (let i = 0; i < TABLE.length; i++) {
    try {
      compiled.push([new RegExp(TABLE[i][0]), TABLE[i][1], TABLE[i][2] || []]);
    } catch (e) { /* a pattern JavaScriptCore will not take is simply skipped */ }
  }

  // `types` empty means the rule is not restricted to a request type.
  function bodyFor(value, type) {
    if (!value) return null;
    let href;
    try {
      const url = new URL(String(value), document.baseURI);
      if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
      href = url.href;
    } catch (e) { return null; }
    for (let i = 0; i < compiled.length; i++) {
      const [re, body, types] = compiled[i];
      if (types.length !== 0 && types.indexOf(type) === -1) continue;
      if (re.test(href)) return body;
    }
    return null;
  }

  // The bodies arrive as data: URLs. fetch and XHR want the decoded text and
  // its type; script and img want the URL as it stands.
  function decode(dataURL) {
    const comma = dataURL.indexOf(',');
    const meta = dataURL.slice(5, comma);
    const isBase64 = meta.endsWith(';base64');
    const mime = (isBase64 ? meta.slice(0, -7) : meta) || 'text/plain';
    const payload = dataURL.slice(comma + 1);
    try {
      return { mime, text: isBase64 ? atob(payload) : decodeURIComponent(payload) };
    } catch (e) { return { mime, text: '' }; }
  }

  // MARK: - fetch

  try {
    const origFetch = window.fetch;
    if (typeof origFetch === 'function') {
      window.fetch = function (input) {
        try {
          const target = typeof input === 'string' ? input : (input && input.url);
          const body = bodyFor(target, 'xhr');
          if (body) {
            const { mime, text } = decode(body);
            return Promise.resolve(new Response(text, {
              status: 200,
              statusText: 'OK',
              headers: { 'Content-Type': mime }
            }));
          }
        } catch (e) { /* fall through to the real fetch */ }
        return origFetch.apply(this, arguments);
      };
    }
  } catch (e) { /* leave fetch alone */ }

  // MARK: - XMLHttpRequest

  try {
    const origOpen = XMLHttpRequest.prototype.open;
    const origSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function (method, url) {
      try { this.__nookStub = bodyFor(url, 'xhr'); } catch (e) { this.__nookStub = null; }
      return origOpen.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function () {
      const stub = this.__nookStub;
      if (!stub) return origSend.apply(this, arguments);
      const xhr = this;
      const body = decode(stub).text;
      try {
        // Shadow the prototype accessors on this instance so the caller reads a
        // finished, empty, successful response.
        Object.defineProperty(xhr, 'readyState', { value: 4, configurable: true });
        Object.defineProperty(xhr, 'status', { value: 200, configurable: true });
        Object.defineProperty(xhr, 'statusText', { value: 'OK', configurable: true });
        Object.defineProperty(xhr, 'responseText', { value: body, configurable: true });
        Object.defineProperty(xhr, 'response', { value: body, configurable: true });
        Object.defineProperty(xhr, 'responseURL', { value: '', configurable: true });
      } catch (e) { return origSend.apply(this, arguments); }
      // Async, like a real response. dispatchEvent also runs the on* handlers,
      // so they must not be called directly as well.
      setTimeout(function () {
        try {
          xhr.dispatchEvent(new Event('readystatechange'));
          xhr.dispatchEvent(new Event('load'));
          xhr.dispatchEvent(new Event('loadend'));
        } catch (e) { /* listener threw; not ours to handle */ }
      }, 0);
    };
  } catch (e) { /* leave XHR alone */ }

  // MARK: - script.src / img.src, set in code

  function patchSrc(proto, type) {
    const desc = Object.getOwnPropertyDescriptor(proto, 'src');
    if (!desc || !desc.set || !desc.get) return;
    Object.defineProperty(proto, 'src', {
      configurable: true,
      enumerable: desc.enumerable,
      get: function () { return desc.get.call(this); },
      set: function (value) {
        try {
          const body = bodyFor(value, type);
          if (body) return desc.set.call(this, body);
        } catch (e) { /* fall through */ }
        return desc.set.call(this, value);
      }
    });
  }

  try { patchSrc(HTMLScriptElement.prototype, 'script'); } catch (e) { /* ignore */ }
  try { patchSrc(HTMLImageElement.prototype, 'image'); } catch (e) { /* ignore */ }

  try {
    const origSetAttribute = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function (name, value) {
      try {
        if (String(name).toLowerCase() === 'src' &&
            (this instanceof HTMLScriptElement || this instanceof HTMLImageElement)) {
          const body = bodyFor(value, this instanceof HTMLScriptElement ? 'script' : 'image');
          if (body) return origSetAttribute.call(this, name, body);
        }
      } catch (e) { /* fall through */ }
      return origSetAttribute.apply(this, arguments);
    };
  } catch (e) { /* leave setAttribute alone */ }
})();
