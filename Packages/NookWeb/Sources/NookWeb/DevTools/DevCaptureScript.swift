// Licensed under GPL-3.0. See LICENSE.
//
//  DevCaptureScript.swift
//  Nook
//
//  The page-world script behind the Console and Network tabs. It has to share the page's world
//  to wrap its console and fetch, so its handler only ever appends log lines.
//

import WebKit

enum DevCaptureScript {
    static let handlerName = "nookDevCapture"
    static let marker = "// Nook Dev Capture"

    static var userScript: WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
    }

    /// Adds or removes the capture and picker scripts. Reads the bridged array fully before
    /// clearing it (Release-only trap).
    static func setInstalled(_ on: Bool, in controller: WKUserContentController) {
        let scripts = [(marker, userScript), (DevPickerScript.marker, DevPickerScript.userScript)]
        let all = Array(controller.userScripts)
        let isDev = { (s: WKUserScript) in scripts.contains { s.source.hasPrefix($0.0) } }
        if on {
            for (mark, script) in scripts where !all.contains(where: { $0.source.hasPrefix(mark) }) {
                controller.addUserScript(script)
            }
        } else if all.contains(where: isDev) {
            let keep = all.nookOwned.filter { !isDev($0) }
            controller.removeAllUserScripts()
            keep.forEach(controller.addUserScript)
        }
    }

    static let source = """
    \(marker)
    (function () {
      if (window.__nookDevCaptureLoaded) return;
      window.__nookDevCaptureLoaded = true;
      const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(handlerName);
      if (!handler) return;
      const post = handler.postMessage.bind(handler);
      const now = performance.now.bind(performance);
      const LIMIT = 65536, QUEUE_MAX = 1000, BATCH = 200;
      let queue = [], timer = null, seq = 0, lost = 0;

      function flush() {
        timer = null;
        const batch = queue.splice(0, BATCH);
        if (lost) { batch.unshift({ k: 'd', n: lost }); lost = 0; }
        if (batch.length) { try { post(batch); } catch (_) {} }
        if (queue.length) timer = setTimeout(flush, 250);
      }
      function push(e) {
        if (queue.length >= QUEUE_MAX) { lost++; return; }
        queue.push(e);
        if (timer === null) timer = setTimeout(flush, 250);
      }

      function fmt(v) {
        try {
          if (typeof v === 'string') return v;
          if (v === undefined) return 'undefined';
          if (typeof v === 'function') return 'ƒ ' + (v.name || 'anonymous') + '()';
          if (typeof v === 'symbol' || typeof v === 'bigint') return String(v);
          // WebKit's stack omits the message, unlike V8's.
          if (v instanceof Error) return String(v) + (v.stack ? '\\n' + v.stack : '');
          if (typeof Node !== 'undefined' && v instanceof Node) {
            if (v.nodeType !== 1) return v.nodeName;
            return '<' + v.tagName.toLowerCase() + (v.id ? '#' + v.id : '') +
              (typeof v.className === 'string' && v.className ? '.' + v.className.trim().split(/\\s+/).join('.') : '') + '>';
          }
          const seen = new WeakSet();
          const s = JSON.stringify(v, (k, x) => {
            if (typeof x === 'object' && x !== null) { if (seen.has(x)) return '[Circular]'; seen.add(x); }
            if (typeof x === 'bigint') return String(x);
            if (typeof x === 'function') return 'ƒ';
            return x;
          }, 2);
          return s === undefined ? String(v) : s;
        } catch (_) {
          try { return String(v); } catch (_) { return '[unprintable]'; }
        }
      }

      for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
        const orig = console[level];
        console[level] = function (...args) {
          try { push({ k: 'c', level, msg: args.map(fmt).join(' ').slice(0, 4000) }); } catch (_) {}
          return orig.apply(this, args);
        };
      }

      addEventListener('error', (ev) => {
        try {
          const el = ev.target;
          if (el && el !== window && el.tagName) {
            push({ k: 'c', level: 'loadError', msg: el.tagName.toLowerCase() + ' ' + (el.currentSrc || el.src || el.href || '') });
          } else {
            push({ k: 'c', level: 'uncaught', msg: String(ev.message), at: ev.filename ? ev.filename + ':' + ev.lineno : undefined });
          }
        } catch (_) {}
      }, true);
      addEventListener('unhandledrejection', (ev) => {
        try { push({ k: 'c', level: 'unhandledRejection', msg: fmt(ev.reason).slice(0, 4000) }); } catch (_) {}
      });

      function absolute(u) { try { return new URL(String(u), location.href).href; } catch (_) { return String(u); } }
      function textual(ct) {
        ct = (ct || '').toLowerCase();
        if (ct.includes('event-stream') || ct.includes('ndjson')) return false;
        return ct.startsWith('text/') || ct.includes('json') || ct.includes('xml') ||
          ct.includes('javascript') || ct.includes('x-www-form-urlencoded');
      }
      function headersOf(h) { const o = {}; try { h.forEach((v, k) => { o[k] = v; }); } catch (_) {} return o; }
      function disguise(wrapper, orig) {
        try { Object.defineProperty(wrapper, 'toString', { value: orig.toString.bind(orig) }); } catch (_) {}
        return wrapper;
      }

      const origFetch = window.fetch;
      if (origFetch) {
        window.fetch = disguise(function (input, init) {
          const id = 'f' + (++seq);
          const t0 = now();
          try {
            const req = (typeof Request !== 'undefined' && input instanceof Request) ? input : null;
            const method = String((init && init.method) || (req && req.method) || 'GET').toUpperCase();
            const reqH = headersOf(new Headers((init && init.headers) || (req && req.headers) || undefined));
            const body = init && init.body;
            push({ k: 'n', id, phase: 'start', kind: 'fetch', method, url: absolute(req ? req.url : input), reqH,
                   reqB: typeof body === 'string' ? body.slice(0, LIMIT) : undefined });
          } catch (_) {}
          const p = origFetch.apply(this, arguments);
          p.then((res) => {
            try {
              const ct = res.headers.get('content-type');
              const len = Number(res.headers.get('content-length') || 0);
              push({ k: 'n', id, phase: 'end', status: res.status, dur: now() - t0, resH: headersOf(res.headers), size: len || undefined });
              if (textual(ct) && len <= LIMIT) {
                res.clone().text().then((t) => push({ k: 'n', id, phase: 'body', resB: t.slice(0, LIMIT) }), () => {});
              }
            } catch (_) {}
          }, (err) => {
            try { push({ k: 'n', id, phase: 'fail', dur: now() - t0, err: String(err) }); } catch (_) {}
          });
          return p;
        }, origFetch);
      }

      const XHR = window.XMLHttpRequest && XMLHttpRequest.prototype;
      if (XHR) {
        const info = new WeakMap();
        const open = XHR.open, send = XHR.send, setHeader = XHR.setRequestHeader;
        XHR.open = disguise(function (method, url) {
          try { info.set(this, { id: 'x' + (++seq), method: String(method).toUpperCase(), url: absolute(url), reqH: {} }); } catch (_) {}
          return open.apply(this, arguments);
        }, open);
        XHR.setRequestHeader = disguise(function (name, value) {
          try { const d = info.get(this); if (d) d.reqH[String(name).toLowerCase()] = String(value); } catch (_) {}
          return setHeader.apply(this, arguments);
        }, setHeader);
        XHR.send = disguise(function (body) {
          const d = info.get(this);
          if (d) {
            try {
              const t0 = now();
              push({ k: 'n', id: d.id, phase: 'start', kind: 'xhr', method: d.method, url: d.url, reqH: d.reqH,
                     reqB: typeof body === 'string' ? body.slice(0, LIMIT) : undefined });
              this.addEventListener('loadend', () => {
                try {
                  if (this.status === 0) { push({ k: 'n', id: d.id, phase: 'fail', dur: now() - t0, err: 'Network error' }); return; }
                  const resH = {};
                  for (const line of this.getAllResponseHeaders().trim().split(/[\\r\\n]+/)) {
                    const i = line.indexOf(':');
                    if (i > 0) resH[line.slice(0, i).trim().toLowerCase()] = line.slice(i + 1).trim();
                  }
                  const text = (this.responseType === '' || this.responseType === 'text') && textual(resH['content-type'])
                    ? this.responseText.slice(0, LIMIT) : undefined;
                  push({ k: 'n', id: d.id, phase: 'end', status: this.status, dur: now() - t0, resH });
                  if (text !== undefined) push({ k: 'n', id: d.id, phase: 'body', resB: text });
                } catch (_) {}
              });
            } catch (_) {}
          }
          return send.apply(this, arguments);
        }, send);
      }

      try {
        new PerformanceObserver((list) => {
          for (const e of list.getEntries()) {
            if (e.initiatorType === 'fetch' || e.initiatorType === 'xmlhttprequest') continue;
            push({ k: 'n', id: 'r' + (++seq), phase: 'res', kind: e.initiatorType || 'other', url: e.name,
                   dur: e.duration, size: e.transferSize || e.decodedBodySize || undefined,
                   status: e.responseStatus || undefined });
          }
        }).observe({ type: 'resource', buffered: true });
      } catch (_) {}

      if (window !== window.top) return;
      function label(el) {
        if (!el || el.nodeType !== 1) return '';
        let s = el.tagName.toLowerCase();
        if (el.id) return s + '#' + el.id;
        if (typeof el.className === 'string' && el.className.trim()) s += '.' + el.className.trim().split(/\\s+/).slice(0, 2).join('.');
        return s;
      }
      function path(el) {
        const parts = [];
        for (let n = el; n && n.nodeType === 1 && n !== document.documentElement; n = n.parentElement) {
          if (n.id) { parts.unshift('#' + CSS.escape(n.id)); break; }
          const same = n.parentElement ? Array.from(n.parentElement.children).filter(c => c.tagName === n.tagName) : [];
          parts.unshift(n.tagName.toLowerCase() + (same.length > 1 ? ':nth-of-type(' + (same.indexOf(n) + 1) + ')' : ''));
        }
        return parts.join(' > ');
      }
      function observe(type, opts, fn) {
        try { new PerformanceObserver((l) => { for (const e of l.getEntries()) { try { fn(e); } catch (_) {} } }).observe(Object.assign({ type, buffered: true }, opts)); } catch (_) {}
      }
      observe('event', { durationThreshold: 16 }, (e) => {
        if (!e.interactionId) return;
        push({ k: 'p', t: 'event', id: e.interactionId, name: e.name, start: e.startTime, dur: e.duration,
               ps: e.processingStart, pe: e.processingEnd, target: label(e.target), path: e.target ? path(e.target) : '' });
      });
      observe('largest-contentful-paint', {}, (e) => {
        push({ k: 'p', t: 'lcp', time: e.renderTime || e.loadTime || e.startTime, size: e.size,
               target: label(e.element), path: e.element ? path(e.element) : '', url: e.url || '' });
      });
      observe('paint', {}, (e) => { if (e.name === 'first-contentful-paint') push({ k: 'p', t: 'fcp', time: e.startTime }); });
      function nav() {
        const n = performance.getEntriesByType('navigation')[0];
        if (n) push({ k: 'p', t: 'nav', ttfb: n.responseStart, dcl: n.domContentLoadedEventEnd, load: n.loadEventEnd });
      }
      if (document.readyState === 'complete') setTimeout(nav, 0);
      else addEventListener('load', () => setTimeout(nav, 0), { once: true });
    })();
    """
}
