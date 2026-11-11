// Nook extension compatibility shim: runs first in every context of a store-built extension.
// Edit scripts/extension-compat/shim.js and run scripts/build-extension-compat.mjs; the copy under Nook/ is generated.
(function () {
  'use strict';
  var g = globalThis;
  // Only where the extension's own code runs: its pages, its worker, its isolated content scripts.
  if (g.__nookCompat || !(g.chrome && g.chrome.runtime && g.chrome.runtime.id)) return;
  // WebKit rebuilds a namespace object nothing refers to, without what was added to it. Each patched one is kept here.
  var keep = g.__nookCompat = [];
  var IDENTITY = '__NOOK_IDENTITY__';
  var inExtensionOrigin = !!g.location && /-extension:$/.test(g.location.protocol);
  // Nook's own native messaging application: the delegate answers it, and no host process carries the name.
  var BRIDGE = 'com.gstudios.nook.compat';
  // True when nativeMessaging is in the manifest only because Nook put it there for this channel.
  var OWNS_CHANNEL = '__NOOK_OWNS_CHANNEL__' === 'true';
  // True when Nook put this shim in the extension's background too.
  var BACKGROUND_SHIM = '__NOOK_BACKGROUND_SHIM__' === 'true';
  // Package paths of the scripts that hold nothing, which Nook lists when it patches the package.
  var EMPTY_SCRIPTS = (function (list) { try { return JSON.parse(list); } catch (e) { return []; } })('__NOOK_EMPTY_SCRIPTS__');

  function message(e) { return String((e && e.message) || e); }
  // A worker, or an MV2 background page.
  function inBackground(root) {
    if (g.clients && g.registration) return true;
    try { return root.extension.getBackgroundPage() === g.window; } catch (e) { return false; }
  }

  // Replaces event.addListener so each listener runs through `through(listener, arguments)`.
  function rewire(event, through) {
    if (!event || typeof event.addListener !== 'function') return;
    keep.push(event);
    var add = event.addListener, remove = event.removeListener, pairs = [];
    function index(f) { for (var i = 0; i < pairs.length; i++) if (pairs[i][0] === f) return i; return -1; }
    event.addListener = function (f) {
      if (typeof f !== 'function' || index(f) >= 0) return undefined;
      var wrapped = function () { return through.call(this, f, Array.prototype.slice.call(arguments)); };
      pairs.push([f, wrapped]);
      return add.apply(event, [wrapped].concat(Array.prototype.slice.call(arguments, 1)));
    };
    event.removeListener = function (f) { var i = index(f); return i < 0 ? undefined : remove.call(event, pairs.splice(i, 1)[0][1]); };
    event.hasListener = function (f) { return index(f) >= 0; };
    // The shim's own listeners are not the extension's.
    event.hasListeners = function () { return pairs.some(function (p) { return !p[0].nookLink; }); };
  }

  // An event nothing in WebKit ever fires. Listeners register and stay silent.
  function inertEvent() {
    var listeners = [];
    return {
      addListener: function (f) { if (listeners.indexOf(f) < 0) listeners.push(f); },
      removeListener: function (f) { listeners = listeners.filter(function (x) { return x !== f; }); },
      hasListener: function (f) { return listeners.indexOf(f) >= 0; },
      hasListeners: function () { return listeners.length > 0; }
    };
  }

  // Answers in the form the caller asked for: its trailing callback, or a promise.
  function answer(args, value) {
    var cb = args.length && typeof args[args.length - 1] === 'function' ? args[args.length - 1] : null;
    if (cb) { cb(value); return undefined; }
    return Promise.resolve(value);
  }

  // The same for a promise that settles later. A failure reaches a callback with runtime.lastError set, as in Chrome.
  // Only WebKit can set that, so the callback rides on a native message Nook answers with the failure.
  function settle(root, args, promise) {
    var cb = args.length && typeof args[args.length - 1] === 'function' ? args[args.length - 1] : null;
    if (!cb) return promise;
    promise.then(function (value) { cb(value); }, function (e) {
      if (!fail) return cb();
      try { fail(message(e), function () { cb(); }); } catch (x) { cb(); }
    });
    return undefined;
  }

  // ponytail: a stub's reply is guessed from its name (lists for getAll and query, false for has and is). Phase 2 replaces stubs with real APIs.
  function emptyReply(name) {
    if (/^(getAll|query|search|getRecent|getContexts)/.test(name)) return [];
    if (/^(has|is|contains)[A-Z]/.test(name)) return false;
    return undefined;
  }
  function stubFunction(name, reply) {
    return function () {
      return answer(arguments, typeof reply === 'function' ? reply.apply(null, arguments) : reply === undefined ? emptyReply(name) : reply);
    };
  }

  // Sets root.a.b when it is missing and the namespace above it exists.
  function add(root, path, make) {
    var parts = path.split('.'), o = root;
    for (var i = 0; i < parts.length - 1; i++) {
      o = o[parts[i]];
      if (!o) return;
      keep.push(o);
    }
    var leaf = parts[parts.length - 1];
    if (o[leaf] === undefined) o[leaf] = make();
  }

  // Replaces obj[name] so that a call WebKit rejects goes to `recover(args, error, original)`.
  function recoverable(obj, name, recover) {
    var original = obj && obj[name];
    if (typeof original !== 'function') return;
    keep.push(obj);
    var call = function (args) { return original.apply(obj, args); };
    obj[name] = function () {
      var args = Array.prototype.slice.call(arguments), out;
      try { out = call(args); } catch (e) { return recover(args, e, call); }
      return out && typeof out.then === 'function' ? out.then(null, function (e) { return recover(args, e, call); }) : out;
    };
  }

  // The channel to Nook. Requests are single native messages; events arrive on one port per context.
  var send = null, fail = null, connect = null, port = null, events = {}, announcing = false, background = false;
  function channel(root) {
    var runtime = root.runtime;
    if (!inExtensionOrigin || typeof runtime.sendNativeMessage !== 'function') return;
    keep.push(runtime);
    // WebKit may stop a background, and Nook then remembers what it listened for.
    background = inBackground(root);
    var sendNative = runtime.sendNativeMessage, connectNative = runtime.connectNative;
    send = function (request) { return sendNative.call(runtime, BRIDGE, request); };
    fail = function (text, callback) { sendNative.call(runtime, BRIDGE, { api: 'nook', method: 'fail', args: [text] }, callback); };
    connect = function () { return connectNative.call(runtime, BRIDGE); };
  }
  function native(api, method, args) {
    if (!send) return Promise.reject(new Error(api + '.' + method + ' is not available'));
    return Promise.resolve().then(function () { return send({ api: api, method: method, args: args || [] }); }).then(function (reply) {
      if (reply && reply.error !== undefined) throw new Error(reply.error);
      // "No value" crosses the channel as null; Chrome's functions resolve with undefined.
      return reply && reply.result !== null ? reply.result : undefined;
    });
  }
  // A function Nook implements. A trailing callback stays here; the other arguments go over the channel.
  function nativeFunction(root, api, method) {
    return function () {
      var args = Array.prototype.slice.call(arguments);
      if (args.length && typeof args[args.length - 1] === 'function') args.pop();
      return settle(root, arguments, native(api, method, args));
    };
  }
  // An event Nook fires. The port opens with the first listener and tells Nook what this context listens for.
  function nativeEvent(name) {
    if (events[name]) return events[name].event;
    var listeners = [];
    events[name] = {
      listening: function () { return listeners.length > 0; },
      fire: function (args) { listeners.slice().forEach(function (f) { try { f.apply(null, args); } catch (e) { console.error(e); } }); },
      event: {
        addListener: function (f) { if (listeners.indexOf(f) < 0) listeners.push(f); announce(); },
        removeListener: function (f) { listeners = listeners.filter(function (x) { return x !== f; }); announce(); },
        hasListener: function (f) { return listeners.indexOf(f) >= 0; },
        hasListeners: function () { return listeners.length > 0; }
      }
    };
    return events[name].event;
  }
  function announce() {
    if (announcing || !connect) return;
    announcing = true;
    // One message for every listener added in this turn: a background script registers them all at once.
    Promise.resolve().then(function () {
      announcing = false;
      try {
        if (!port) {
          port = connect();
          port.onMessage.addListener(function (m) { var e = m && events[m.event]; if (e) e.fire(m.args || []); });
          port.onDisconnect.addListener(function () { port = null; });
        }
        port.postMessage({ subscribe: Object.keys(events).filter(function (n) { return events[n].listening(); }), lazy: background });
      } catch (e) {}
    });
  }

  // Nook put nativeMessaging in the manifest for the channel. The extension is answered as its own manifest reads.
  function ownChannel(root) {
    var permissions = root.permissions, NAME = 'nativeMessaging';
    if (!OWNS_CHANNEL || !send || !permissions) return;
    // runtime.sendNativeMessage and connectNative stay visible: WebKit lets nothing replace a member of `runtime`
    // (measured). Nook refuses every host but its own for such an extension.
    keep.push(permissions);
    var original = { getAll: permissions.getAll, contains: permissions.contains, request: permissions.request, remove: permissions.remove };
    function asks(query) { return !!query && Array.isArray(query.permissions) && query.permissions.indexOf(NAME) >= 0; }
    // The query without the name, or null when nothing else is in it.
    function rest(query) {
      var others = query.permissions.filter(function (p) { return p !== NAME; });
      return others.length || (query.origins && query.origins.length) ? Object.assign({}, query, { permissions: others }) : null;
    }
    permissions.getAll = function () {
      return settle(root, arguments, Promise.all([original.getAll.call(permissions), native('nook', 'nativeMessagingGranted')]).then(function (found) {
        var all = Object.assign({}, found[0]);
        all.permissions = (all.permissions || []).filter(function (p) { return p !== NAME || found[1]; });
        return all;
      }));
    };
    // Each of the three asks Nook about nativeMessaging and WebKit about whatever else the query holds.
    [['contains', 'nativeMessagingGranted'], ['request', 'requestNativeMessaging'], ['remove', 'removeNativeMessaging']].forEach(function (pair) {
      permissions[pair[0]] = function (query) {
        if (!asks(query)) return original[pair[0]].apply(permissions, arguments);
        return settle(root, arguments, native('nook', pair[1]).then(function (yes) {
          var others = rest(query);
          return yes && others ? original[pair[0]].call(permissions, others) : !!yes;
        }));
      };
    });
  }

  // A store build asks which browser it is in. Under Nook's Safari user agent it takes paths its package was never tested on.
  function identity() {
    var chrome = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/__CHROME_MAJOR__.0.0.0 Safari/537.36';
    var ua = {
      chrome: chrome,
      edge: chrome + ' Edg/__CHROME_MAJOR__.0.0.0',
      firefox: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:__FIREFOX_MAJOR__.0) Gecko/20100101 Firefox/__FIREFOX_MAJOR__.0'
    }[IDENTITY];
    if (!ua) return;
    var proto = Object.getPrototypeOf(g.navigator);
    function define(name, value) { Object.defineProperty(proto, name, { get: function () { return value; }, configurable: true, enumerable: true }); }
    define('userAgent', ua);
    define('appVersion', ua.slice(8));
    define('vendor', IDENTITY === 'firefox' ? '' : 'Google Inc.');
    if (IDENTITY !== 'firefox' && !('userAgentData' in g.navigator)) {
      var brands = [{ brand: 'Chromium', version: '__CHROME_MAJOR__' }, { brand: IDENTITY === 'edge' ? 'Microsoft Edge' : 'Google Chrome', version: '__CHROME_MAJOR__' }];
      var data = { brands: brands, mobile: false, platform: 'macOS' };
      define('userAgentData', Object.assign({
        getHighEntropyValues: function () { return Promise.resolve(Object.assign({ architecture: 'arm', bitness: '64', platformVersion: '15.0.0', uaFullVersion: '__CHROME_MAJOR__.0.0.0', fullVersionList: brands }, data)); },
        toJSON: function () { return data; }
      }, data));
    }
  }

  function globals() {
    if (typeof g.requestIdleCallback === 'function') return;
    g.requestIdleCallback = function (callback) {
      return setTimeout(function () { callback({ didTimeout: false, timeRemaining: function () { return 10; } }); }, 1);
    };
    g.cancelIdleCallback = function (id) { clearTimeout(id); };
  }

  // WebKit runs the waiting microtasks when an imported script returns, and Chrome does not. A worker that counts on
  // Chrome's order around the import of an empty file (Tampermonkey's startup test) keeps it: nothing is imported.
  function imports() {
    var original = g.importScripts;
    if (!inExtensionOrigin || typeof original !== 'function' || !Array.isArray(EMPTY_SCRIPTS) || !EMPTY_SCRIPTS.length) return;
    g.importScripts = function () {
      var rest = Array.prototype.filter.call(arguments, function (url) {
        try {
          // `origin` is of no use here: a URL of a scheme the parser does not know has none.
          var u = new URL(url, g.location.href), own = u.protocol === g.location.protocol && u.host === g.location.host;
          return !own || EMPTY_SCRIPTS.indexOf(decodeURIComponent(u.pathname).slice(1)) < 0;
        } catch (e) { return true; }
      });
      return rest.length ? original.apply(g, rest) : undefined;
    };
  }

  // Chrome holds a content script's message until the worker has started. WebKit answers it at once with nothing while
  // the worker has no listener yet, as on its first run after an install or an update. So a content script's first
  // message waits until the worker's shim answers a question no listener of the extension's ever sees.
  var PING = '__nookCompatPing', gated = false;
  function startup(root) {
    var runtime = root.runtime;
    if (gated || !runtime.onMessage || typeof runtime.onMessage.addListener !== 'function') return;
    gated = true;
    keep.push(runtime);
    function asks(m) { return !!m && typeof m === 'object' && m[PING] === 1; }
    if (inExtensionOrigin) {
      if (inBackground(root)) runtime.onMessage.addListener(function (m, sender, reply) { if (asks(m)) reply(true); });
      rewire(runtime.onMessage, function (f, args) { return asks(args[0]) ? undefined : f.apply(this, args); });
      return;
    }
    // Without the shim in the background nobody would answer, and the extension's own listeners would be asked.
    var sendMessage = runtime.sendMessage, up = false, waiting = null;
    if (!BACKGROUND_SHIM || typeof sendMessage !== 'function') return;
    function started() {
      if (waiting) return waiting;
      // By the clock: a hidden page's timers run late.
      var question = {}, pause = 25, began = Date.now();
      question[PING] = 1;
      return waiting = new Promise(function (done) {
        function go() { up = true; done(); }
        (function ask() {
          var asked;
          try { asked = sendMessage.call(runtime, question); } catch (e) { return go(); }
          Promise.resolve(asked).then(function (yes) {
            // ponytail: gives up after about 4 s, and a worker slower than that is messaged as it was before.
            if (yes === true || Date.now() - began >= 4000) return go();
            setTimeout(ask, pause);
            pause = Math.min(pause * 2, 400);
          }, go);
        })();
      });
    }
    runtime.sendMessage = function () {
      if (up) return sendMessage.apply(runtime, arguments);
      var args = arguments, sent = started().then(function () { return sendMessage.apply(runtime, args); });
      return typeof args[args.length - 1] === 'function' ? undefined : sent;
    };
  }

  // WebKit's address patterns have no port and match every port of a host. Chrome's may name one.
  var PORT = /^([a-z*][a-z0-9+.*-]*:\/\/[^\/:\[]+):(\d+|\*)(?=\/|$)/i;
  function portless(value) {
    if (Array.isArray(value)) return value.map(portless);
    return typeof value === 'string' ? value.replace(PORT, '$1') : value;
  }
  function badPattern(e) { return /not a valid pattern|invalid match pattern/.test(message(e)); }

  // Calls WebKit throws on and Chrome and Firefox answer.
  function answers(root) {
    // A permission name WebKit does not know is a permission the extension does not have.
    ['contains', 'request', 'remove'].forEach(function (name) {
      recoverable(root.permissions, name, function (args, e) {
        var origins = args[0] && args[0].origins;
        if (badPattern(e) && String(portless(origins)) !== String(origins)) {
          return root.permissions[name].apply(root.permissions, [Object.assign({}, args[0], { origins: portless(origins) })].concat(args.slice(1)));
        }
        if (!/is not a valid permission/.test(message(e))) throw e;
        return answer(args, false);
      });
    });
    // A tab search by address keeps to the port that was asked for.
    recoverable(root.tabs, 'query', function (args, e, call) {
      var query = args[0], url = query && query.url, bare = portless(url);
      if (!badPattern(e) || String(bare) === String(url)) throw e;
      var asked = [].concat(url).map(function (p) { return (PORT.exec(p) || [])[2] || '*'; });
      function kept(tabs) {
        if (!Array.isArray(tabs) || asked.indexOf('*') >= 0) return tabs;
        return tabs.filter(function (t) {
          try { var u = new URL(t.url); return asked.indexOf(u.port || (u.protocol === 'https:' ? '443' : '80')) >= 0; } catch (x) { return true; }
        });
      }
      var rest = args.slice(1), cb = typeof rest[rest.length - 1] === 'function' ? rest.pop() : null;
      var next = [Object.assign({}, query, { url: bare })];
      return cb ? call(next.concat([function (tabs) { cb(kept(tabs)); }])) : call(next).then(kept);
    });
    // ponytail: a content script registered for one port runs on the host's other ports too. WebKit has no narrower pattern.
    ['registerContentScripts', 'updateContentScripts'].forEach(function (name) {
      recoverable(root.scripting, name, function (args, e, call) {
        if (!badPattern(e) || !Array.isArray(args[0])) throw e;
        var scripts = args[0].map(function (s) {
          if (!s || typeof s !== 'object') return s;
          var out = Object.assign({}, s);
          if (s.matches) out.matches = portless(s.matches);
          if (s.excludeMatches) out.excludeMatches = portless(s.excludeMatches);
          return out;
        });
        if (JSON.stringify(scripts) === JSON.stringify(args[0])) throw e;
        return call([scripts].concat(args.slice(1)));
      });
    });
    // An unknown or empty message name gives the empty string.
    recoverable(root.i18n, 'getMessage', function () { return ''; });
    // WebKit wants a plain object here; a class instance or an object from another realm is refused.
    ['local', 'sync', 'session'].forEach(function (area) {
      var storage = root.storage && root.storage[area];
      if (storage) keep.push(root.storage);
      recoverable(storage, 'set', function (args, e, call) {
        if (!/object is expected/.test(message(e)) || !args[0] || typeof args[0] !== 'object') throw e;
        return call([JSON.parse(JSON.stringify(args[0]))].concat(args.slice(1)));
      });
    });
    // A filter with a pattern WebKit cannot parse (ws://) keeps its other patterns.
    ['onBeforeRequest', 'onBeforeSendHeaders', 'onSendHeaders', 'onHeadersReceived', 'onAuthRequired', 'onResponseStarted',
     'onBeforeRedirect', 'onCompleted', 'onErrorOccurred'].forEach(function (name) {
      var event = root.webRequest && root.webRequest[name];
      if (event) keep.push(root.webRequest);
      recoverable(event, 'addListener', function (args, e, call) {
        for (var tries = 0; tries < 20; tries++) {
          var bad = /'([^']+)' is an invalid match pattern/.exec(message(e)), filter = args[1];
          if (!bad || !filter || !Array.isArray(filter.urls)) throw e;
          var urls = filter.urls.filter(function (u) { return u !== bad[1]; });
          if (urls.length === filter.urls.length) throw e;
          // Nothing left this listener could match.
          if (!urls.length) return undefined;
          args = args.slice();
          args[1] = Object.assign({}, filter, { urls: urls });
          try { return call(args); } catch (next) { e = next; }
        }
        return undefined;
      });
    });
    ruleBatches(root.declarativeNetRequest);
    // Chrome still takes the MV2 names for the toolbar button's menu. WebKit knows one name per manifest version.
    [root.contextMenus, root.menus !== root.contextMenus ? root.menus : null].forEach(function (menus) {
      ['create', 'update'].forEach(function (name, at) {
        recoverable(menus, name, function (args, e, call) {
          for (var tries = 0; tries < 8; tries++) {
            var bad = /'([^']+)' is not a valid context/.exec(message(e)), props = args[at];
            if (!bad || !props || !Array.isArray(props.contexts)) throw e;
            var contexts = props.contexts.filter(function (c) { return c !== bad[1]; });
            if (/^(browser|page)_action$/.test(bad[1]) && contexts.indexOf('action') < 0) contexts.push('action');
            // No context left that WebKit can show the item in.
            if (!contexts.length) return props.id;
            args = args.slice();
            args[at] = Object.assign({}, props, { contexts: contexts });
            try { return call(args); } catch (next) { e = next; }
          }
          throw e;
        });
      });
    });
  }

  // WebKit rejects a whole batch when one rule uses something it lacks. The rest of the batch still goes in.
  function ruleBatches(dnr) {
    if (!dnr) return;
    keep.push(dnr);
    var SINGLE_DROPS = 40;
    ['updateSessionRules', 'updateDynamicRules'].forEach(function (name) {
      var original = dnr[name];
      if (typeof original !== 'function') return;
      dnr[name] = function (options, callback) {
        if (!options || !Array.isArray(options.addRules) || !options.addRules.length) return original.apply(dnr, arguments);
        var rules = options.addRules.slice(), dropped = 0;
        function attempt(n) {
          var out;
          try { out = Promise.resolve(original.call(dnr, Object.assign({}, options, { addRules: rules }))); } catch (e) { out = Promise.reject(e); }
          return out.catch(function (e) {
            var at = /rule at index (\d+)/.exec(message(e));
            if (!at || !rules.length) throw e;
            var before = rules.length;
            // ponytail: one call per bad rule, capped. Past the cap the two kinds WebKit rejects most go at once, then the batch. Checking rules before the call would be exact.
            if (n < SINGLE_DROPS) rules.splice(+at[1], 1);
            else if (n === SINGLE_DROPS) rules = rules.filter(function (r) { return !(r.condition && r.condition.regexFilter) && !(r.action && r.action.type === 'modifyHeaders'); });
            else rules = [];
            dropped += before - rules.length;
            return attempt(n + 1);
          });
        }
        var done = attempt(0).then(function (value) {
          if (dropped) console.warn('[Nook] declarativeNetRequest.' + name + ': ' + dropped + ' rules left out, WebKit does not support them');
          return value;
        });
        if (typeof callback !== 'function') return done;
        done.then(function () { callback(); }, function () { callback(); });
        return undefined;
      };
    });
  }

  // Namespaces Nook implements natively, each for an extension whose manifest asks for it. Nook checks the same thing.
  function bridged(root, T) {
    if (!send) return;
    var declared = root.runtime.getManifest().permissions || [];
    Object.keys(T.bridged).forEach(function (name) {
      var def = T.bridged[name];
      if (declared.indexOf(def.permission) < 0) return;
      add(root, name, function () {
        var o = {};
        def.functions.forEach(function (f) { o[f] = nativeFunction(root, name, f); });
        def.events.forEach(function (e) { o[e] = nativeEvent(name + '.' + e); });
        Object.keys(def.enums).forEach(function (e) { o[e] = def.enums[e]; });
        return o;
      });
    });
    // Chrome answers this one at once, with the address a provider sends the person back to.
    if (root.identity && T.bridged.identity && declared.indexOf('identity') >= 0) {
      root.identity.getRedirectURL = function (path) {
        return 'https://' + root.runtime.id + '.chromiumapp.org/' + String(path === undefined ? '' : path).replace(/^\//, '');
      };
    }
    Object.keys(T.bridgedEvents).forEach(function (path) {
      if (declared.indexOf(T.bridgedEvents[path]) >= 0) add(root, path, function () { return tabEvent(root, path); });
    });
    // runtime.getContexts answers for the offscreen document, the one context only Nook knows of.
    if (root.offscreen && T.bridged.offscreen) {
      windowlessTabs(root);
      workerClients(root);
      workerLink(root);
      add(root, 'runtime.getContexts', function () {
        return function (filter) {
          var wanted = filter && typeof filter === 'object' ? filter : {};
          function allows(key, value) { return !Array.isArray(wanted[key]) || wanted[key].indexOf(value) >= 0; }
          return settle(root, arguments, native('offscreen', 'document').then(function (doc) {
            if (!doc || wanted.incognito === true) return [];
            var context = { contextType: 'OFFSCREEN_DOCUMENT', contextId: doc.documentId, documentId: doc.documentId, documentUrl: doc.url,
                            documentOrigin: doc.url.split('/').slice(0, 3).join('/'), frameId: 0, tabId: -1, windowId: -1, incognito: false };
            var keys = { contextTypes: 'contextType', contextIds: 'contextId', documentIds: 'documentId', documentUrls: 'documentUrl',
                         documentOrigins: 'documentOrigin', frameIds: 'frameId', tabIds: 'tabId', windowIds: 'windowId' };
            return Object.keys(keys).every(function (k) { return allows(k, context[keys[k]]); }) ? [context] : [];
          }));
        };
      });
    }
  }

  // Chrome's UrlFilter, for a listener added with { url: [...] }: any one filter, every key of it.
  function urlMatches(filters, href) {
    var list = filters && filters.url, u;
    if (!Array.isArray(list) || !list.length) return true;
    try { u = new URL(href); } catch (e) { return false; }
    var tests = {}, bare = u.href.split('#')[0], port = +u.port || { 'http:': 80, 'https:': 443 }[u.protocol] || 0;
    function four(name, text, form) {
      form = form || function (v) { return v; };
      tests[name + 'Contains'] = function (v) { return text.indexOf(v) >= 0; };
      tests[name + 'Equals'] = function (v) { return text === form(v); };
      tests[name + 'Prefix'] = function (v) { return text.startsWith(form(v)); };
      tests[name + 'Suffix'] = function (v) { return text.endsWith(v); };
    }
    // Chrome matches a host with a dot in front, so '.example.com' finds the domain and its subdomains.
    four('host', '.' + u.hostname, function (v) { return v.charAt(0) === '.' ? v : '.' + v; });
    four('path', u.pathname);
    four('query', u.search.slice(1));
    four('url', bare);
    tests.urlMatches = function (v) { return new RegExp(v).test(bare); };
    tests.originAndPathMatches = function (v) { return new RegExp(v).test(u.origin + u.pathname); };
    tests.schemes = function (v) { return v.indexOf(u.protocol.slice(0, -1)) >= 0; };
    tests.ports = function (v) { return v.some(function (p) { return Array.isArray(p) ? port >= p[0] && port <= p[1] : port === p; }); };
    return list.some(function (filter) {
      return Object.keys(filter).every(function (key) { try { return !!tests[key] && !!tests[key](filter[key]); } catch (e) { return false; } });
    });
  }

  // An event Nook fires about a tab names the tab by address and place: WebKit keeps its tab ids to itself.
  // WebKit's own tabs.onUpdated for the same change carries the id, and the two are paired by address.
  var tabWatch = null;
  function tabIds(root) {
    if (tabWatch) return tabWatch;
    var seen = [], waiting = [], resolved = new WeakMap();
    root.tabs.onUpdated.addListener(function (id, change) {
      var url = change && change.url;
      if (!url) return;
      for (var i = 0; i < waiting.length; i++) if (waiting[i].url === url) { waiting.splice(i, 1)[0].done(id); return; }
      seen.push({ id: id, url: url, at: Date.now() });
      if (seen.length > 20) seen.shift();
    });
    function find(details) {
      for (var i = seen.length - 1; i >= 0; i--) {
        if (seen[i].url === details.url && Date.now() - seen[i].at < 2000) return Promise.resolve(seen.splice(i, 1)[0].id);
      }
      return new Promise(function (done) {
        var entry = { url: details.url, done: done };
        waiting.push(entry);
        setTimeout(function () {
          var i = waiting.indexOf(entry);
          if (i < 0) return;
          waiting.splice(i, 1);
          // No update came, as after a worker restart: the one tab at that address, by its place when two share it.
          Promise.resolve().then(function () { return root.tabs.query({}); }).then(function (tabs) {
            var same = tabs.filter(function (t) { return t.url === details.url; });
            var placed = same.filter(function (t) { return t.index === details.tabIndex; });
            done(same.length === 1 ? same[0].id : placed.length === 1 ? placed[0].id : undefined);
          }, function () { done(undefined); });
        }, 400);
      });
    }
    // One answer per event, however many listeners ask.
    return tabWatch = function (details) {
      if (!resolved.has(details)) resolved.set(details, find(details));
      return resolved.get(details);
    };
  }
  function tabEvent(root, name) {
    var source = nativeEvent(name), pairs = [];
    function index(f) { for (var i = 0; i < pairs.length; i++) if (pairs[i][0] === f) return i; return -1; }
    return {
      addListener: function (f, filters) {
        if (typeof f !== 'function' || index(f) >= 0 || !root.tabs) return;
        var tabId = tabIds(root);
        var through = function (details) {
          if (!details || !urlMatches(filters, details.url)) return;
          tabId(details).then(function (id) {
            if (id === undefined) return;
            var out = Object.assign({}, details, { tabId: id });
            delete out.tabIndex;
            try { f(out); } catch (e) { console.error(e); }
          });
        };
        pairs.push([f, through]);
        source.addListener(through);
      },
      removeListener: function (f) { var i = index(f); if (i >= 0) source.removeListener(pairs.splice(i, 1)[0][1]); },
      hasListener: function (f) { return index(f) >= 0; },
      hasListeners: function () { return pairs.length > 0; }
    };
  }

  // WebKit routes runtime messages to the offscreen document only as a tab, so Nook announces it as one that sits in
  // no window. The extension must not see that tab: its tab events are dropped, and its messages carry no sender.tab.
  function windowlessTabs(root) {
    function windowless(info) { return !!info && info.windowId === -1; }
    function dropping(position) {
      return function (f, args) { return windowless(args[position]) ? undefined : f.apply(this, args); };
    }
    if (root.tabs) {
      keep.push(root.tabs);
      rewire(root.tabs.onCreated, dropping(0));
      rewire(root.tabs.onUpdated, dropping(2));
      rewire(root.tabs.onRemoved, dropping(1));
    }
    function withoutTab(sender) {
      if (!sender || !windowless(sender.tab)) return sender;
      var plain = Object.assign({}, sender);
      delete plain.tab;
      return plain;
    }
    rewire(root.runtime.onMessage, function (f, args) { args[1] = withoutTab(args[1]); return f.apply(this, args); });
    rewire(root.runtime.onConnect, function (f, args) {
      var port = args[0];
      // The link to the worker is the shim's own port.
      if (port && (port.name === LINK || port.name === PAGE_LINK)) return f.nookLink ? f.apply(this, args) : undefined;
      if (f.nookLink) return undefined;
      try { if (port && windowless(port.sender && port.sender.tab)) delete port.sender.tab; } catch (e) {}
      return f.apply(this, args);
    });
  }

  // WebKit connects no extension page to the extension's service worker: clients.matchAll() is empty in the worker and
  // ServiceWorker.postMessage from a page arrives nowhere. Both run over one runtime port: the offscreen document's
  // from its start, as the worker's client, and any other page's from the first message it posts.
  var LINK = 'nook.compat.worker', PAGE_LINK = LINK + '.page';
  // ponytail: messages cross as JSON, so an ArrayBuffer or a Blob does not survive, and a port sent through a port is dropped.
  function link(port, side, deliver) {
    var ports = {}, made = 0;
    function relay(local, key) {
      ports[key] = local;
      local.onmessage = function (e) { try { port.postMessage({ to: key, data: e.data }); } catch (x) {} };
    }
    port.onMessage.addListener(function (m) {
      if (!m) return;
      if (m.to !== undefined) { if (ports[m.to]) ports[m.to].postMessage(m.data); return; }
      deliver(m.data, (m.ports || []).map(function (key) { var c = new MessageChannel(); relay(c.port2, key); return c.port1; }));
    });
    return function (data, transfer) {
      var list = Array.isArray(transfer) ? transfer : (transfer && transfer.transfer) || [];
      var keys = list.filter(function (p) { return !!p && typeof p.postMessage === 'function'; }).map(function (p) { var key = side + made++; relay(p, key); return key; });
      port.postMessage({ data: data, ports: keys });
    };
  }

  // In the worker: the offscreen document is a client, as in Chrome, where extensions find theirs with clients.matchAll().
  function workerClients(root) {
    var clients = g.clients;
    if (!clients || typeof clients.matchAll !== 'function' || !root.offscreen || keep.indexOf(clients) >= 0) return;
    keep.push(clients);
    var pages = [], waiting = [], count = 0;
    var onLink = function (port) {
      var client = { id: 'nook-offscreen-' + (++count), url: (port.sender && port.sender.url) || '', type: 'window', frameType: 'top-level', focused: false, visibilityState: 'hidden' };
      client.postMessage = link(port, 'w', function (data, ports) {
        var e = new MessageEvent('message', { data: data, ports: ports });
        Object.defineProperty(e, 'source', { value: client });
        e.waitUntil = function () {};
        g.dispatchEvent(e);
      });
      // Only the offscreen document is listed as a client. Another page is answered through the message's source.
      if (port.name !== LINK) return;
      pages.push(client);
      port.onDisconnect.addListener(function () { pages = pages.filter(function (c) { return c !== client; }); });
      waiting.splice(0).forEach(function (f) { f(); });
    };
    onLink.nookLink = true;
    root.runtime.onConnect.addListener(onLink);
    var matchAll = clients.matchAll, get = clients.get;
    clients.matchAll = function (options) {
      var type = (options && options.type) || 'window';
      return matchAll.call(clients, options).then(function (found) {
        if (type !== 'window' && type !== 'all') return found;
        if (pages.length) return found.concat(pages);
        // A restarted worker has no link yet to a document that outlived the last one. Nook asks the document for it.
        return native('offscreen', 'link').then(function (exists) {
          if (!exists || pages.length) return found.concat(pages);
          return new Promise(function (done) { waiting.push(done); setTimeout(done, 2000); }).then(function () { return found.concat(pages); });
        }, function () { return found; });
      });
    };
    clients.get = function (id) {
      var mine = pages.filter(function (c) { return c.id === id; })[0];
      return mine ? Promise.resolve(mine) : get.call(clients, id);
    };
  }

  // In an extension page: what it posts to the worker goes over the link. Nook marks the offscreen document before this runs.
  function workerLink(root) {
    var sw = g.navigator && g.navigator.serviceWorker, proto = g.ServiceWorker && g.ServiceWorker.prototype;
    if (inBackground(root) || !sw || !proto || keep.indexOf(sw) >= 0) return;
    keep.push(sw);
    var offscreen = !!g.__nookOffscreen, post = null, active = null;
    function open() {
      if (post) return post;
      var port = root.runtime.connect({ name: offscreen ? LINK : PAGE_LINK });
      post = link(port, 'p', function (data, ports) {
        var e = new MessageEvent('message', { data: data, ports: ports });
        Object.defineProperty(e, 'source', { value: active });
        sw.dispatchEvent(e);
      });
      port.onDisconnect.addListener(function () { post = null; });
      return post;
    }
    // A page whose extension has been unloaded posts to nobody, as before.
    proto.postMessage = function (data, transfer) { try { open()(data, transfer); } catch (e) {} };
    try { sw.getRegistration().then(function (r) { active = (r && r.active) || null; }, function () {}); } catch (e) {}
    if (!offscreen) return;
    // Nook asks for the link again when a restarted worker looks for its document.
    g.addEventListener('nook-relink', function () { try { open(); } catch (e) {} });
    // WebKit leaves `controller` null in an extension page. Chrome sets it for the offscreen document.
    var controller = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(sw), 'controller');
    if (controller && controller.get) {
      Object.defineProperty(sw, 'controller', { get: function () { return controller.get.call(sw) || active; }, configurable: true });
    }
    try { open(); } catch (e) {}
  }

  // What Chrome defines and WebKit lacks in the namespaces both have, and the few namespaces whose absence stops a background script at startup.
  function tables() { return __NOOK_TABLES__; }
  function surface(root) {
    add(root, 'storage.managed', function () {
      return { get: stubFunction('get', {}), set: stubFunction('set'), remove: stubFunction('remove'), clear: stubFunction('clear'),
               getBytesInUse: stubFunction('getBytesInUse', 0), getKeys: stubFunction('getKeys', []), onChanged: inertEvent() };
    });
    if (IDENTITY === 'firefox') {
      add(root, 'runtime.getBrowserInfo', function () {
        return stubFunction('getBrowserInfo', { name: 'Firefox', vendor: 'Mozilla', version: '__FIREFOX_MAJOR__.0', buildID: '20260101000000' });
      });
    }
    // A content script stops here, as in Chrome, and never parses the tables.
    if (!inExtensionOrigin) return;
    var T = tables();
    bridged(root, T);
    Object.keys(T.enums).forEach(function (path) { add(root, path, function () { return T.enums[path]; }); });
    T.events.forEach(function (path) { add(root, path, inertEvent); });
    // A build told it runs in Chrome calls Chrome's functions without asking whether they exist.
    if (IDENTITY !== 'firefox') {
      var replies = {
        'action.getUserSettings': { isOnToolbar: true },
        'action.getBadgeTextColor': [255, 255, 255, 255],
        'cookies.getPartitionKey': {},
        'declarativeNetRequest.getAvailableStaticRuleCount': 30000,
        'declarativeNetRequest.getDisabledRuleIds': [],
        'declarativeNetRequest.testMatchOutcome': { matchedRules: [] },
        'i18n.detectLanguage': { isReliable: false, languages: [] },
        'runtime.requestUpdateCheck': { status: 'no_update' },
        'tabs.getZoomSettings': { mode: 'automatic', scope: 'per-origin', defaultZoomFactor: 1 }
      };
      T.functions.forEach(function (path) { add(root, path, function () { return stubFunction(path.split('.')[1], replies[path]); }); });
    }

    function self() {
      var m = root.runtime.getManifest();
      return { id: root.runtime.id, name: m.name, shortName: m.short_name || m.name, version: m.version, description: m.description || '',
               enabled: true, mayDisable: true, installType: 'normal', type: 'extension', permissions: m.permissions || [], hostPermissions: m.host_permissions || [] };
    }
    var known = {
      management: { getSelf: stubFunction('getSelf', self) },
      // Nothing is shown, and the extension is told so.
      notifications: {
        create: stubFunction('create', function (id) { return typeof id === 'string' ? id : 'nook-' + Date.now(); }),
        getAll: stubFunction('getAll', {}), getPermissionLevel: stubFunction('getPermissionLevel', 'denied')
      }
    };
    Object.keys(T.stubs).forEach(function (name) {
      var def = T.stubs[name];
      add(root, name, function () {
        var o = {};
        def.functions.forEach(function (f) { o[f] = stubFunction(f); });
        def.events.forEach(function (e) { o[e] = inertEvent(); });
        Object.keys(def.enums).forEach(function (e) { o[e] = def.enums[e]; });
        // Read-only settings: each reports a value the extension cannot change.
        Object.keys(def.settings).forEach(function (group) {
          o[group] = {};
          Object.keys(def.settings[group]).forEach(function (s) {
            o[group][s] = { get: stubFunction('get', { value: def.settings[group][s], levelOfControl: 'not_controllable' }),
                            set: stubFunction('set'), clear: stubFunction('clear'), onChange: inertEvent() };
          });
        });
        return Object.assign(o, known[name]);
      });
    });
  }

  // Each part stands alone: a failure in one must never stop the extension's own code from loading.
  [identity, globals, imports].forEach(function (part) { try { part(); } catch (e) {} });
  var roots = g.browser && g.browser !== g.chrome ? [g.chrome, g.browser] : [g.chrome];
  roots.forEach(function (root) {
    [channel, startup, answers, ownChannel, surface].forEach(function (part) { try { part(root); } catch (e) {} });
  });
})();
