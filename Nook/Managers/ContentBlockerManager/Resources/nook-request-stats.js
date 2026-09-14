// Nook Content Blocker
// Request stats observer: reports resource URLs a page tries to load so native
// can count how many the content blocker stopped. Observe only; never blocks,
// delays, or alters any request.
(function () {
  'use strict';

  if (window.__nookRequestStatsLoaded) return;
  window.__nookRequestStatsLoaded = true;

  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nookRequestStats;
  if (!handler) return;

  const FLUSH_MS = 250;
  const MAX_PER_MESSAGE = 200;
  const MAX_SEEN = 5000;
  const RESOURCE_TAGS = 'img,source,script,link,iframe,frame,video,audio,track,object,embed';

  const seen = new Set();
  let batch = [];
  let timer = 0;

  function log() {
    if (window.__nookRequestStatsVerbose === true) console.log.apply(console, ['[NookRequestStats]'].concat(Array.prototype.slice.call(arguments)));
  }

  function flush() {
    timer = 0;
    if (!batch.length) return;
    const pending = batch;
    batch = [];
    for (let i = 0; i < pending.length; i += MAX_PER_MESSAGE) {
      try {
        handler.postMessage({ requests: pending.slice(i, i + MAX_PER_MESSAGE) });
      } catch (e) { log('postMessage failed', e); }
    }
  }

  function record(value, type) {
    try {
      if (!value) return;
      const url = new URL(String(value), document.baseURI);
      if (url.protocol !== 'http:' && url.protocol !== 'https:') return;
      const href = url.href;
      if (seen.has(href)) return;
      if (seen.size >= MAX_SEEN) seen.clear();
      seen.add(href);
      batch.push({ url: href, type: type });
      log(type, href);
      if (!timer) timer = setTimeout(flush, FLUSH_MS);
    } catch (e) { /* invalid URL or similar; ignore */ }
  }

  // MARK: - Network API hooks

  try {
    const origFetch = window.fetch;
    if (typeof origFetch === 'function') {
      window.fetch = function (input) {
        try {
          record(typeof Request === 'function' && input instanceof Request ? input.url : input, 'xmlhttprequest');
        } catch (e) { /* ignore */ }
        return origFetch.apply(this, arguments);
      };
    }
  } catch (e) { /* ignore */ }

  try {
    const origOpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function (method, url) {
      try { record(url, 'xmlhttprequest'); } catch (e) { /* ignore */ }
      return origOpen.apply(this, arguments);
    };
  } catch (e) { /* ignore */ }

  try {
    const origBeacon = navigator.sendBeacon;
    if (typeof origBeacon === 'function') {
      navigator.sendBeacon = function (url) {
        try { record(url, 'ping'); } catch (e) { /* ignore */ }
        return origBeacon.apply(this, arguments);
      };
    }
  } catch (e) { /* ignore */ }

  try {
    const OrigWebSocket = window.WebSocket;
    if (typeof OrigWebSocket === 'function') {
      const WrappedWebSocket = function WebSocket(url, protocols) {
        try { record(url, 'websocket'); } catch (e) { /* ignore */ }
        return arguments.length > 1 ? new OrigWebSocket(url, protocols) : new OrigWebSocket(url);
      };
      WrappedWebSocket.prototype = OrigWebSocket.prototype;
      for (const key of ['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED']) WrappedWebSocket[key] = OrigWebSocket[key];
      window.WebSocket = WrappedWebSocket;
    }
  } catch (e) { /* ignore */ }

  // MARK: - DOM resource observation

  function firstSrcsetURL(srcset) {
    const first = String(srcset).trim().split(',')[0];
    return first ? first.trim().split(/\s+/)[0] : '';
  }

  function linkType(el) {
    const rel = (el.getAttribute('rel') || '').toLowerCase().split(/\s+/);
    if (rel.includes('stylesheet')) return 'stylesheet';
    if (rel.includes('preload') || rel.includes('prefetch') || rel.includes('modulepreload')) {
      switch ((el.getAttribute('as') || '').toLowerCase()) {
        case 'script': return 'script';
        case 'style': return 'stylesheet';
        case 'image': return 'image';
        case 'font': return 'font';
        case 'fetch': return 'xmlhttprequest';
        case 'video': case 'audio': case 'track': return 'media';
        case 'document': return 'sub_frame';
        default: return 'other';
      }
    }
    return null; // icon, canonical, dns-prefetch etc. are not resource loads we care about
  }

  function inspect(el) {
    const tag = el.localName;
    let value = null;
    let type = 'other';
    switch (tag) {
      case 'img':
        type = 'image';
        value = el.getAttribute('src') || firstSrcsetURL(el.getAttribute('srcset') || '');
        break;
      case 'source':
        type = el.parentElement && el.parentElement.localName === 'picture' ? 'image' : 'media';
        value = el.getAttribute('src') || firstSrcsetURL(el.getAttribute('srcset') || '');
        break;
      case 'script': type = 'script'; value = el.getAttribute('src'); break;
      case 'link': type = linkType(el); value = el.getAttribute('href'); break;
      case 'iframe': case 'frame': type = 'sub_frame'; value = el.getAttribute('src'); break;
      case 'video': case 'audio': case 'track': type = 'media'; value = el.getAttribute('src'); break;
      case 'object': type = 'object'; value = el.getAttribute('data'); break;
      case 'embed': type = 'object'; value = el.getAttribute('src'); break;
      default: value = el.getAttribute('src');
    }
    if (type && value) record(value, type);
  }

  function onMutations(mutations) {
    try {
      for (const m of mutations) {
        if (m.type === 'attributes') {
          if (m.target.nodeType === 1) inspect(m.target);
          continue;
        }
        for (const node of m.addedNodes) {
          if (node.nodeType !== 1) continue;
          inspect(node);
          const nested = node.querySelectorAll(RESOURCE_TAGS);
          for (let i = 0; i < nested.length; i++) inspect(nested[i]);
        }
      }
    } catch (e) { log('mutation error', e); }
  }

  function observe(root) {
    try {
      new MutationObserver(onMutations).observe(root, {
        childList: true, subtree: true, attributes: true, attributeFilter: ['src', 'href', 'srcset', 'data']
      });
    } catch (e) { log('observe failed', e); }
  }

  if (document.documentElement) {
    observe(document.documentElement);
  } else {
    // Document start in a frame before <html> exists: wait for it.
    const bootstrap = new MutationObserver(function () {
      if (!document.documentElement) return;
      bootstrap.disconnect();
      observe(document.documentElement);
    });
    bootstrap.observe(document, { childList: true });
  }

  // MARK: - Flush on page teardown

  window.addEventListener('pagehide', flush, true);
  document.addEventListener('visibilitychange', function () {
    if (document.visibilityState === 'hidden') flush();
  }, true);
})();
