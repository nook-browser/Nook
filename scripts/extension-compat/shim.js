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

  function message(e) { return String((e && e.message) || e); }

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

  // Calls WebKit throws on and Chrome and Firefox answer.
  function answers(root) {
    // A permission name WebKit does not know is a permission the extension does not have.
    ['contains', 'request', 'remove'].forEach(function (name) {
      recoverable(root.permissions, name, function (args, e) {
        if (!/is not a valid permission/.test(message(e))) throw e;
        return answer(args, false);
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
  [identity, globals].forEach(function (part) { try { part(); } catch (e) {} });
  var roots = g.browser && g.browser !== g.chrome ? [g.chrome, g.browser] : [g.chrome];
  roots.forEach(function (root) {
    [answers, surface].forEach(function (part) { try { part(root); } catch (e) {} });
  });
})();
