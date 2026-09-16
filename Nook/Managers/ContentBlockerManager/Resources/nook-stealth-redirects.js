// Nook Content Blocker
// Stealth redirects: answer known ad URLs with an inert stub instead of letting
// the content rule list fail them. A blocked request fails loudly (fetch
// rejects, XHR reports status 0, script/img fire error) and anti-adblock
// services read exactly those signals. A stub loads normally and does nothing,
// so there is nothing to detect and still no ad.
//
// Covers requests JavaScript starts: fetch, XMLHttpRequest, and script/img
// elements built in code. It cannot cover a <script src> written in the page's
// own HTML: WebKit begins that load as the parser reaches the tag, before any
// observer could rewrite it. Those stay blocked and stay visible as errors.
//
// Everything not in TABLE is untouched and still blocked by the rule lists.
(function () {
  'use strict';

  if (window.__nookStealthRedirectsLoaded) return;
  window.__nookStealthRedirectsLoaded = true;

  // Inert stubs. An empty script and a 1x1 transparent GIF, as data: URLs so
  // the browser loads them itself and fires the real load event.
  const JS_STUB = 'data:application/javascript,';
  const GIF_STUB = 'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';

  // Phase 1 is hand-seeded with the loaders that anti-adblock scripts probe.
  // Later this comes from the $redirect rules already in the filter lists.
  // Deliberately not here yet: gpt.js and google-ima.js are API shims, not
  // empty files, so an empty stub can break a page worse than a blocked one.
  // Add them with a real shim, and a site that proves each one is needed.
  // Never stub Ad-Shield (html-load.*, ad-shield CDN mirrors). It compares the
  // script it receives against an X-Length response header, and a data: URL
  // carries no headers, so an empty stub reads as "script malformed" and it
  // escalates: on jeepforum.com it replaced the whole document with an
  // error-report.com modal. Blocking it outright is the milder failure.
  const TABLE = [
    [/\/pagead\/js\/adsbygoogle\.js/, 'js'],   // Google AdSense loader
    [/a\.pub\.network\/core\/imgs\//, 'img']   // Freestar detection image
  ];

  function stubFor(value) {
    if (!value) return null;
    let href;
    try {
      const url = new URL(String(value), document.baseURI);
      if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
      href = url.href;
    } catch (e) { return null; }
    for (let i = 0; i < TABLE.length; i++) {
      if (TABLE[i][0].test(href)) return TABLE[i][1];
    }
    return null;
  }

  function stubURL(kind) { return kind === 'img' ? GIF_STUB : JS_STUB; }

  // MARK: - fetch

  try {
    const origFetch = window.fetch;
    if (typeof origFetch === 'function') {
      window.fetch = function (input) {
        try {
          const target = typeof input === 'string' ? input : (input && input.url);
          const kind = stubFor(target);
          if (kind) {
            const body = kind === 'img' ? new Blob([], { type: 'image/gif' }) : '';
            return Promise.resolve(new Response(body, {
              status: 200,
              statusText: 'OK',
              headers: { 'Content-Type': kind === 'img' ? 'image/gif' : 'application/javascript' }
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
      try { this.__nookStub = stubFor(url); } catch (e) { this.__nookStub = null; }
      return origOpen.apply(this, arguments);
    };

    XMLHttpRequest.prototype.send = function () {
      const kind = this.__nookStub;
      if (!kind) return origSend.apply(this, arguments);
      const xhr = this;
      const body = '';
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

  function patchSrc(proto) {
    const desc = Object.getOwnPropertyDescriptor(proto, 'src');
    if (!desc || !desc.set || !desc.get) return;
    Object.defineProperty(proto, 'src', {
      configurable: true,
      enumerable: desc.enumerable,
      get: function () { return desc.get.call(this); },
      set: function (value) {
        try {
          const kind = stubFor(value);
          if (kind) return desc.set.call(this, stubURL(kind));
        } catch (e) { /* fall through */ }
        return desc.set.call(this, value);
      }
    });
  }

  try { patchSrc(HTMLScriptElement.prototype); } catch (e) { /* ignore */ }
  try { patchSrc(HTMLImageElement.prototype); } catch (e) { /* ignore */ }

  try {
    const origSetAttribute = Element.prototype.setAttribute;
    Element.prototype.setAttribute = function (name, value) {
      try {
        if (String(name).toLowerCase() === 'src' &&
            (this instanceof HTMLScriptElement || this instanceof HTMLImageElement)) {
          const kind = stubFor(value);
          if (kind) return origSetAttribute.call(this, name, stubURL(kind));
        }
      } catch (e) { /* fall through */ }
      return origSetAttribute.apply(this, arguments);
    };
  } catch (e) { /* leave setAttribute alone */ }
})();
