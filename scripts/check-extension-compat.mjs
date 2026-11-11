// Runs the generated shim against a stand-in for WebKit's extension API, which throws where
// WebKit throws, and checks what the extension's code would then see.
//   node scripts/check-extension-compat.mjs
import assert from 'assert/strict';
import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import path from 'path';
import vm from 'vm';

const root = path.dirname(fileURLToPath(new URL('.', import.meta.url)));
const shim = readFileSync(path.join(root, 'Nook/Managers/ExtensionManager/NookExtensionCompat.js'), 'utf8');

// Built inside the context, so its objects share a realm with the shim's as they do in WebKit.
const webkit = `
  function invalid(what, why) { return new Error('Invalid call to ' + what + '(). ' + why); }
  class Navigator {}
  Object.defineProperty(Navigator.prototype, 'userAgent', { get() { return 'Safari'; }, configurable: true });
  globalThis.navigator = new Navigator();
  globalThis.chrome = {
    runtime: { id: KIND === 'page' ? undefined : 'abc', getManifest() { return { name: 'N', version: '1.2' }; } },
    i18n: { getMessage(name) { if (!name) throw invalid('i18n.getMessage', "The 'name' value is invalid, because it cannot be empty."); return 'text:' + name; } },
    storage: { local: { set(items) {
      if (Object.getPrototypeOf(items) !== Object.prototype) throw invalid('storageArea.set', "The 'items' value is invalid, because an object is expected.");
      this.saved = items; return Promise.resolve();
    } } },
  };
  // Nook on the other end of the channel: answers requests, and posts events down any open port.
  globalThis.nook = { requests: [], ports: [], granted: false, document: null, post(m) { this.ports.forEach(p => p.deliver(m)); } };
  if (KIND === 'extension') {
    chrome.runtime.getManifest = () => ({ name: 'N', version: '1.2', permissions: PERMISSIONS });
    chrome.runtime.sendNativeMessage = (application, request, callback) => {
      // WebKit sets runtime.lastError for the length of a callback whose message failed.
      if (callback) { chrome.runtime.lastError = { message: 'Invalid call to runtime.sendNativeMessage(). ' + request.args[0] }; callback(); delete chrome.runtime.lastError; return undefined; }
      nook.requests.push(application + ' ' + request.api + '.' + request.method);
      if (application !== 'com.gstudios.nook.compat') return Promise.reject(new Error('host not found'));
      const key = request.api + '.' + request.method;
      if (key === 'offscreen.createDocument') {
        if (nook.document) return Promise.resolve({ error: 'Only a single offscreen document may be created.' });
        nook.document = { url: 'webkit-extension://abc/' + request.args[0].url, documentId: 'doc-1' };
        return Promise.resolve({ result: null });
      }
      if (key === 'offscreen.document') return Promise.resolve({ result: nook.document });
      if (key === 'offscreen.hasDocument') return Promise.resolve({ result: !!nook.document });
      if (key === 'offscreen.link') return Promise.resolve({ result: false });
      if (key === 'notifications.create') return Promise.resolve({ result: typeof request.args[0] === 'string' ? request.args[0] : 'made-up-id' });
      if (key === 'idle.queryState') return Promise.resolve(typeof request.args[0] === 'number' ? { result: 'active' } : { error: 'A detection interval in seconds is required.' });
      if (key === 'nook.nativeMessagingGranted') return Promise.resolve({ result: nook.granted });
      if (key === 'nook.requestNativeMessaging') { nook.granted = true; return Promise.resolve({ result: true }); }
      return Promise.resolve({ error: key + ' is not available' });
    };
    chrome.runtime.connectNative = application => {
      const listeners = [];
      const port = { application, posted: [], onMessage: { addListener: f => listeners.push(f) }, onDisconnect: { addListener() {} },
                     postMessage(m) { this.posted.push(m); }, deliver(m) { listeners.forEach(f => f(m)); } };
      nook.ports.push(port);
      return port;
    };
  }
  // An event whose listeners the check can fire, as WebKit would.
  function liveEvent() {
    const listeners = [];
    return { addListener: f => { listeners.push(f); }, removeListener: f => { listeners.splice(listeners.indexOf(f), 1); },
             hasListener: f => listeners.includes(f), fire: (...args) => listeners.map(f => f(...args)), count: () => listeners.length };
  }
  chrome.runtime.onMessage = liveEvent();
  chrome.runtime.onConnect = liveEvent();
  // WebKit's patterns have no port: one that names a port is refused, as one with no scheme is.
  const refused = p => typeof p !== 'string' || !p.includes('://') || p.split('://')[1].split('/')[0].includes(':');
  if (KIND === 'extension') Object.assign(chrome, {
    scripting: { registerContentScripts(scripts) {
      for (const s of scripts) for (const m of s.matches || []) if (refused(m)) return Promise.reject(invalid('scripting.registerContentScripts', "Script with ID '" + s.id + "' has an invalid match pattern '" + m + "'."));
      this.registered = scripts; return Promise.resolve();
    } },
    webNavigation: {}, action: {},
    tabs: { onCreated: liveEvent(), onUpdated: liveEvent(), onRemoved: liveEvent(), query(query) {
      for (const u of [].concat((query && query.url) || [])) if (refused(u)) throw invalid('tabs.query', "The 'url' value is invalid, because '" + u + "' is not a valid pattern.");
      const tabs = Promise.resolve(globalThis.TABS || []), cb = arguments[arguments.length - 1];
      return typeof cb === 'function' ? void tabs.then(cb) : tabs;
    } },
    permissions: {
      contains(query) {
        for (const p of query.permissions || []) if (p !== 'tabs' && p !== 'nativeMessaging') throw invalid('permissions.contains', "The 'permissions' value is invalid, because '" + p + "' is not a valid permission.");
        for (const o of query.origins || []) if (refused(o)) throw invalid('permissions.contains', "The 'origins' value is invalid, because '" + o + "' is not a valid pattern.");
        this.asked = query.origins;
        return Promise.resolve(true);
      },
      getAll() { return Promise.resolve({ permissions: ['tabs', 'nativeMessaging'], origins: [] }); },
      request(query) { return Promise.resolve(true); },
    },
    contextMenus: { made: [], create(props) {
      for (const c of props.contexts || []) if (!['all', 'page', 'link', 'action'].includes(c)) throw invalid('menus.create', "The 'contexts' value is invalid, because '" + c + "' is not a valid context.");
      this.made.push(props.contexts.join('+')); return props.id;
    } },
    webRequest: { onBeforeRequest: { addListener(listener, filter) {
      for (const u of filter.urls) if (/^wss?:/.test(u)) throw invalid('addListener', "The 'urls' value is invalid, because '" + u + "' is an invalid match pattern.");
      this.urls = filter.urls;
    } } },
    declarativeNetRequest: { calls: 0, updateSessionRules(options) {
      this.calls++;
      const i = options.addRules.findIndex(r => r.bad);
      if (i >= 0) return Promise.reject(invalid('declarativeNetRequest.updateSessionRules', "The 'addRules' value is invalid, because an error with rule at index " + i + ': Rule with id ' + options.addRules[i].id + ' is invalid.'));
      this.rules = options.addRules; return Promise.resolve();
    } },
  });
  globalThis.browser = chrome;
`;

function load(identity, kind = 'extension', { permissions = [], ownsChannel = false, globals = {}, before = '', empty = null, backgroundShim = true } = {}) {
    const location = kind === 'extension' ? { protocol: 'webkit-extension:', host: 'abc', href: 'webkit-extension://abc/sw.js' }
                                          : { protocol: 'https:', host: 'site.test', href: 'https://site.test/' };
    const context = vm.createContext({ KIND: kind, PERMISSIONS: permissions, location, setTimeout, clearTimeout, URL, console: { warn() {}, error() {} }, ...globals });
    vm.runInContext(webkit, context);
    vm.runInContext(before, context);
    // The patcher writes the list of empty scripts as a string holding JSON. A shim it never touched has none.
    const listed = empty ? shim.replace("'__NOOK_EMPTY_SCRIPTS__'", JSON.stringify(JSON.stringify(empty))) : shim;
    vm.runInContext(listed.replace('__NOOK_IDENTITY__', identity).replace('__NOOK_OWNS_CHANNEL__', String(ownsChannel))
        .replace('__NOOK_BACKGROUND_SHIM__', String(backgroundShim)), context);
    return { context, run: code => vm.runInContext(code, context) };
}

// The extension's own pages and worker, as a Chrome store build.
const { context, run } = load('chrome');
assert.match(run('navigator.userAgent'), / Chrome\/\d+\./);
assert.equal(run('navigator.userAgentData.brands[1].brand'), 'Google Chrome');
assert.equal(run('typeof requestIdleCallback'), 'function');

assert.equal(await run(`chrome.permissions.contains({ permissions: ['bookmarks'] })`), false);
assert.equal(await run(`chrome.permissions.contains({ permissions: ['tabs'] })`), true);
assert.equal(await run(`new Promise(done => chrome.permissions.contains({ permissions: ['tabs', 'offscreen'] }, done))`), false);

// An address pattern with a port, which Chrome takes and WebKit refuses, is asked again without it.
assert.equal(await run(`chrome.permissions.contains({ origins: ['http://localhost:8080/*', 'https://example.com/*', '*://*.example.org:*/*'] })`), true);
assert.equal(run(`JSON.stringify(chrome.permissions.asked)`), '["http://localhost/*","https://example.com/*","*://*.example.org/*"]');
// Both of WebKit's refusals in one call, each in its turn.
assert.equal(await run(`chrome.permissions.contains({ permissions: ['bookmarks'], origins: ['http://localhost:*/*'] })`), false);
// A pattern that is wrong for another reason is still an error.
await assert.rejects(async () => run(`chrome.permissions.contains({ origins: ['nonsense'] })`), /not a valid pattern/);
// A tab search keeps to the port that was asked for, since WebKit's pattern matches them all.
run(`globalThis.TABS = [{ id: 1, url: 'http://localhost:8080/a' }, { id: 2, url: 'http://localhost:3000/b' }, { id: 3, url: 'http://localhost/c' }]`);
const found = code => run(`(${code}).then(tabs => tabs.map(t => t.id).join())`);
assert.equal(await found(`chrome.tabs.query({ url: 'http://localhost:8080/*' })`), '1');
assert.equal(await found(`chrome.tabs.query({ url: ['http://localhost:80/*', 'http://localhost:3000/*'] })`), '2,3');
assert.equal(await found(`chrome.tabs.query({ url: 'http://localhost:*/*' })`), '1,2,3');
assert.equal(await found(`chrome.tabs.query({ url: 'http://localhost/*' })`), '1,2,3');
assert.equal(await found(`new Promise(done => chrome.tabs.query({ url: 'http://localhost:3000/*' }, done))`), '2');
assert.throws(() => run(`chrome.tabs.query({ url: 'nonsense' })`), /not a valid pattern/);
run(`globalThis.TABS = undefined`);
// A content script registered for one port is registered for the host.
await run(`chrome.scripting.registerContentScripts([{ id: 'a', matches: ['http://localhost:3000/*', 'https://example.com/*'], js: ['a.js'] }])`);
assert.equal(run(`JSON.stringify(chrome.scripting.registered[0].matches)`), '["http://localhost/*","https://example.com/*"]');
await assert.rejects(async () => run(`chrome.scripting.registerContentScripts([{ id: 'b', matches: ['nonsense'], js: ['a.js'] }])`), /invalid match pattern/);

assert.equal(run(`chrome.i18n.getMessage('')`), '');
assert.equal(run(`chrome.i18n.getMessage('title')`), 'text:title');

await run(`chrome.storage.local.set(new (class State { constructor() { this.a = 1; } })())`);
assert.equal(run('JSON.stringify(chrome.storage.local.saved)'), '{"a":1}');
assert.equal(run('Object.getPrototypeOf(chrome.storage.local.saved) === Object.prototype'), true);

run(`chrome.webRequest.onBeforeRequest.addListener(() => {}, { urls: ['ws://*/*', 'https://a.example/*', 'wss://*/*'] })`);
assert.equal(run('chrome.webRequest.onBeforeRequest.urls.join()'), 'https://a.example/*');
run(`chrome.webRequest.onBeforeRequest.urls = null; chrome.webRequest.onBeforeRequest.addListener(() => {}, { urls: ['ws://*/*'] })`);
assert.equal(run('chrome.webRequest.onBeforeRequest.urls'), null);

// One rejected rule leaves the batch; the rest goes in.
await run(`chrome.declarativeNetRequest.updateSessionRules({ addRules: [{ id: 1 }, { id: 2, bad: true }, { id: 3 }] })`);
assert.equal(run('chrome.declarativeNetRequest.rules.map(r => r.id).join()'), '1,3');
// Hundreds of rejected rules cost a bounded number of calls, then the kinds WebKit rejects most go at once.
run('chrome.declarativeNetRequest.calls = 0');
await run(`chrome.declarativeNetRequest.updateSessionRules({ addRules: Array.from({ length: 500 }, (_, i) =>
    i % 2 ? { id: i, bad: true, condition: { regexFilter: 'x' } } : { id: i }) })`);
assert.ok(run('chrome.declarativeNetRequest.calls') <= 43, 'retries are capped');
assert.equal(run('chrome.declarativeNetRequest.rules.length'), 250);
assert.equal(await run(`new Promise(done => chrome.declarativeNetRequest.updateSessionRules({ addRules: [{ id: 9, bad: true }] }, () => done('called')))`), 'called');

// Enums and events Chrome defines, added where the namespace exists and only there.
assert.equal(run('chrome.runtime.OnInstalledReason.INSTALL'), 'install');
assert.equal(run('chrome.scripting.ExecutionWorld.ISOLATED'), 'ISOLATED');
assert.equal(run('typeof chrome.runtime.onUpdateAvailable.addListener'), 'function');
assert.equal(run('typeof chrome.webNavigation.onHistoryStateUpdated.addListener'), 'function');
assert.equal(run('chrome.windows'), undefined);
// A Chrome build also gets Chrome's functions in those namespaces.
assert.equal((await run('chrome.action.getUserSettings()')).isOnToolbar, true);
assert.equal(JSON.stringify(await run('chrome.runtime.getContexts({})')), '[]');
assert.equal(JSON.stringify(await run('chrome.storage.managed.get()')), '{}');

// The stubbed namespaces are plain objects with every member; the rest stay undefined.
assert.equal(run(`'create' in chrome.notifications && 'onButtonClicked' in chrome.notifications`), true);
assert.equal(run(`chrome.notifications.onClicked.addListener(() => {})`), undefined);
assert.equal(await run('chrome.notifications.getPermissionLevel()'), 'denied');
assert.equal(await run(`chrome.notifications.create('id-1', {})`), 'id-1');
assert.equal((await run('chrome.management.getSelf()')).name, 'N');
assert.equal((await run('chrome.privacy.services.passwordSavingEnabled.get({})')).levelOfControl, 'not_controllable');
assert.equal(run('chrome.privacy.IPHandlingPolicy.DEFAULT'), 'default');
for (const absent of ['offscreen', 'sidePanel', 'identity', 'downloads', 'idle']) {
    assert.equal(run(`chrome.${absent}`), undefined, `${absent} is not stubbed`);
}

// A menu for the toolbar button under its MV2 name goes in under the name WebKit knows, and an unknown context is left out.
assert.equal(run(`chrome.contextMenus.create({ id: 'a', title: 't', contexts: ['browser_action', 'page'] })`), 'a');
assert.equal(run(`chrome.contextMenus.create({ id: 'b', title: 't', contexts: ['page_action', 'action', 'launcher'] })`), 'b');
assert.equal(run(`chrome.contextMenus.create({ id: 'c', title: 't', contexts: ['launcher'] })`), 'c');
assert.equal(run(`chrome.contextMenus.made.join()`), 'page+action,action');
// Any other failure is the extension's to see.
assert.throws(() => run(`chrome.contextMenus.create({ id: 'd', title: 't', contexts: 5 })`), /not iterable/);

// Every patched namespace object is held, or WebKit rebuilds it bare.
assert.ok(run('__nookCompat.includes(chrome.scripting) && __nookCompat.includes(chrome.permissions)'));
// A second copy of the shim in the same context does nothing.
const held = run('__nookCompat.length');
vm.runInContext(shim.replace('__NOOK_IDENTITY__', 'firefox'), context);
assert.equal(run('__nookCompat.length'), held);
assert.match(run('navigator.userAgent'), / Chrome\//);

// A Firefox add-on is told it runs in Firefox.
const firefox = load('firefox');
assert.match(firefox.run('navigator.userAgent'), / Firefox\/\d+/);
assert.equal(firefox.run('navigator.userAgentData'), undefined);
assert.equal((await firefox.run('browser.runtime.getBrowserInfo()')).name, 'Firefox');
assert.equal(firefox.run('browser.runtime.getContexts'), undefined);

// A content script gets the identity and the answers, and no namespace Chrome would not give it.
const content = load('chrome', 'content');
assert.match(content.run('navigator.userAgent'), / Chrome\//);
assert.equal(content.run(`chrome.i18n.getMessage('')`), '');
assert.equal(content.run('chrome.notifications'), undefined);
assert.equal(content.run('chrome.runtime.OnInstalledReason'), undefined);

// In a page's own world there is no extension, and the shim leaves everything alone.
const page = load('chrome', 'page');
assert.equal(page.run('navigator.userAgent'), 'Safari');
assert.equal(page.run('typeof __nookCompat'), 'undefined');

// The native bridge. An API exists only for an extension whose manifest asks for it.
assert.equal(run('chrome.offscreen'), undefined);
const bridged = load('chrome', 'extension', { permissions: ['offscreen', 'nativeMessaging'], ownsChannel: true });
assert.equal(bridged.run(`typeof chrome.offscreen.createDocument + ' ' + chrome.offscreen.Reason.DOM_PARSER`), 'function DOM_PARSER');
assert.equal(await bridged.run(`chrome.offscreen.createDocument({ url: 'off.html', reasons: ['DOM_PARSER'], justification: 'x' })`), undefined);
assert.equal(await bridged.run('chrome.offscreen.hasDocument()'), true);
// A failure is a rejection, or runtime.lastError for the length of a callback.
await assert.rejects(bridged.run(`chrome.offscreen.createDocument({ url: 'off.html', reasons: ['DOM_PARSER'] })`), /Only a single offscreen document/);
assert.equal(await bridged.run(`new Promise(done => chrome.offscreen.createDocument({ url: 'off.html', reasons: ['BLOBS'] }, () => done(chrome.runtime.lastError.message)))`),
             'Invalid call to runtime.sendNativeMessage(). Only a single offscreen document may be created.');
assert.equal(bridged.run('chrome.runtime.lastError'), undefined);
// runtime.getContexts answers for the offscreen document, and honours the filter.
const contexts = await bridged.run(`chrome.runtime.getContexts({ contextTypes: ['OFFSCREEN_DOCUMENT'] })`);
assert.equal(contexts.length, 1);
assert.equal(contexts[0].documentUrl, 'webkit-extension://abc/off.html');
assert.equal(contexts[0].documentOrigin, 'webkit-extension://abc');
assert.equal((await bridged.run(`chrome.runtime.getContexts({ contextTypes: ['TAB'] })`)).length, 0);
assert.equal((await bridged.run(`chrome.runtime.getContexts({ documentUrls: ['webkit-extension://abc/other.html'] })`)).length, 0);
// The offscreen document is a tab only to WebKit. The extension hears nothing of a tab in no window,
// and a message from the document carries no sender.tab, as in Chrome.
bridged.run(`globalThis.seen = [];
  globalThis.onCreated = t => seen.push('created ' + t.id); chrome.tabs.onCreated.addListener(onCreated);
  chrome.tabs.onUpdated.addListener((id, change, t) => seen.push('updated ' + id));
  chrome.tabs.onRemoved.addListener((id, info) => seen.push('removed ' + id));
  chrome.runtime.onMessage.addListener((m, sender, reply) => { seen.push(m + ' tab:' + (sender.tab ? sender.tab.id : 'none')); return m === 'async'; });`);
bridged.run(`chrome.tabs.onCreated.fire({ id: 1, windowId: 7 }); chrome.tabs.onCreated.fire({ id: 2, windowId: -1 });
  chrome.tabs.onUpdated.fire(1, {}, { id: 1, windowId: 7 }); chrome.tabs.onUpdated.fire(2, {}, { id: 2, windowId: -1 });
  chrome.tabs.onRemoved.fire(1, { windowId: 7 }); chrome.tabs.onRemoved.fire(2, { windowId: -1 });`);
assert.equal(bridged.run('seen.join()'), 'created 1,updated 1,removed 1');
assert.equal(bridged.run(`JSON.stringify(chrome.runtime.onMessage.fire('page', { tab: { id: 1, windowId: 7 } }, () => {}))`), '[false]');
assert.equal(bridged.run(`JSON.stringify(chrome.runtime.onMessage.fire('async', { url: 'x', tab: { id: 2, windowId: -1 } }, () => {}))`), '[true]');
assert.equal(bridged.run('seen.slice(3).join()'), 'page tab:1,async tab:none');
// A listener is added once, is found again, and comes off.
assert.equal(bridged.run(`chrome.tabs.onCreated.addListener(onCreated); chrome.tabs.onCreated.count() + ' ' + chrome.tabs.onCreated.hasListener(onCreated)`), '1 true');
assert.equal(bridged.run(`chrome.tabs.onCreated.removeListener(onCreated); chrome.tabs.onCreated.count() + ' ' + chrome.tabs.onCreated.hasListener(onCreated)`), '0 false');
// An extension without the offscreen API keeps WebKit's events as they are.
assert.equal(run(`chrome.tabs.onCreated.addListener.toString().includes('listeners.push')`), true);

// Every request went to Nook's own application and nowhere else.
assert.ok(bridged.run('nook.requests.length > 0 && nook.requests.every(r => r.startsWith("com.gstudios.nook.compat "))'));

// nativeMessaging is in the manifest only as Nook's channel, so the extension is told it has none.
assert.equal(JSON.stringify((await bridged.run('chrome.permissions.getAll()')).permissions), '["tabs"]');
assert.equal(await bridged.run(`chrome.permissions.contains({ permissions: ['nativeMessaging'] })`), false);
assert.equal(await bridged.run(`chrome.permissions.contains({ permissions: ['tabs'] })`), true);
// Once the person grants it through Nook, it shows.
assert.equal(await bridged.run(`chrome.permissions.request({ permissions: ['nativeMessaging', 'tabs'] })`), true);
assert.equal(await bridged.run(`chrome.permissions.contains({ permissions: ['nativeMessaging'] })`), true);
assert.equal(JSON.stringify((await bridged.run('chrome.permissions.getAll()')).permissions), '["tabs","nativeMessaging"]');
// An extension that declared nativeMessaging itself is not second-guessed.
const own = load('chrome', 'extension', { permissions: ['offscreen', 'nativeMessaging'], ownsChannel: false });
assert.equal(JSON.stringify((await own.run('chrome.permissions.getAll()')).permissions), '["tabs","nativeMessaging"]');
assert.ok(own.run('nook.requests.length === 0'));

// webNavigation's two same-document events. Nook names the tab by address and place; the id comes from
// WebKit's own tabs.onUpdated for the same change, whichever of the two arrives first.
assert.equal(run('chrome.webNavigation.onHistoryStateUpdated.hasListeners()'), false);
const navigating = load('chrome', 'extension', { permissions: ['webNavigation'] });
const pause = ms => new Promise(done => setTimeout(done, ms));
const fire = (url, tabIndex = 0) => navigating.run(`nook.post({ event: 'webNavigation.onHistoryStateUpdated', args: [{ url: '${url}', tabIndex: ${tabIndex}, frameId: 0 }] })`);
navigating.run(`globalThis.got = [];
  const on = chrome.webNavigation.onHistoryStateUpdated;
  on.addListener(d => got.push(d.tabId + ' ' + d.url + ' ' + ('tabIndex' in d)));
  on.addListener(d => got.push('suffix'), { url: [{ hostSuffix: 'example.com', pathPrefix: '/a' }] });
  on.addListener(d => got.push('equals'), { url: [{ hostEquals: 'example.com' }, { hostEquals: 'www.example.com', ports: [[400, 500]] }] });
  on.addListener(d => got.push('dotted'), { url: [{ hostContains: '.example.', schemes: ['https'], queryContains: 'x=1' }] });
  on.addListener(d => got.push('regex'), { url: [{ urlMatches: '^https://www[.]example[.]com/a[?]x=[0-9]$' }] });
  on.addListener(d => got.push('other'), { url: [{ hostPrefix: 'example' }, { urlEquals: 'https://www.example.com/a' }, { unknownKey: 'x' }] });`);
await pause(5);
assert.equal(JSON.stringify(navigating.run('nook.ports[0].posted.pop()')), '{"subscribe":["webNavigation.onHistoryStateUpdated"],"lazy":false}');
navigating.run(`chrome.tabs.onUpdated.fire(7, { url: 'https://www.example.com:443/a?x=1#top' }, {})`);
fire('https://www.example.com:443/a?x=1#top');
await pause(5);
assert.equal(navigating.run('got.sort().join()'), '7 https://www.example.com:443/a?x=1#top false,dotted,equals,regex,suffix');
// Nook's event first, then the update.
navigating.run('got.length = 0');
fire('https://other.test/b');
navigating.run(`chrome.tabs.onUpdated.fire(9, { status: 'complete' }, {}); chrome.tabs.onUpdated.fire(9, { url: 'https://other.test/b' }, {})`);
await pause(5);
assert.equal(navigating.run('got.join()'), '9 https://other.test/b false');
// No update, as after a worker restart: the tab is found by address, and by place when two tabs share it.
navigating.run(`got.length = 0; globalThis.TABS = [{ id: 4, url: 'https://q.test/', index: 2 }, { id: 5, url: 'https://q.test/', index: 3 }, { id: 6, url: 'https://one.test/', index: 9 }]`);
fire('https://q.test/', 3);
fire('https://one.test/', 0);
fire('https://nowhere.test/', 0);
await pause(450);
assert.equal(navigating.run('got.sort().join()'), '5 https://q.test/ false,6 https://one.test/ false');
// A removed listener hears nothing more, and Nook is told when the last one goes.
navigating.run(`globalThis.one = d => got.push('one'); chrome.webNavigation.onReferenceFragmentUpdated.addListener(one);`);
await pause(5);
assert.equal(navigating.run('nook.ports[0].posted.pop().subscribe.length'), 2);
navigating.run(`chrome.webNavigation.onReferenceFragmentUpdated.removeListener(one)`);
await pause(5);
assert.equal(navigating.run('nook.ports[0].posted.pop().subscribe.join()'), 'webNavigation.onHistoryStateUpdated');

// idle: asked of Nook, and told by Nook. An extension that did not ask for it has no such namespace.
assert.equal(navigating.run('chrome.idle'), undefined);
const idling = load('chrome', 'extension', { permissions: ['idle'] });
assert.equal(await idling.run('chrome.idle.queryState(60)'), 'active');
assert.equal(await idling.run(`new Promise(done => chrome.idle.queryState('soon', () => done(chrome.runtime.lastError.message)))`), 'Invalid call to runtime.sendNativeMessage(). A detection interval in seconds is required.');
assert.equal(idling.run('chrome.idle.IdleState.LOCKED'), 'locked');
idling.run(`globalThis.states = []; chrome.idle.onStateChanged.addListener(s => states.push(s))`);
await pause(5);
assert.equal(idling.run('nook.ports[0].posted.pop().subscribe.join()'), 'idle.onStateChanged');
idling.run(`nook.post({ event: 'idle.onStateChanged', args: ['locked'] }); nook.post({ event: 'idle.onOther', args: ['x'] })`);
assert.equal(idling.run('states.join()'), 'locked');

// notifications: real for an extension that declares it, and the phase 1 stand-in, which shows nothing, for one that does not.
assert.equal(await idling.run('chrome.notifications.getPermissionLevel()'), 'denied');
const notifying = load('chrome', 'extension', { permissions: ['notifications'] });
assert.equal(await notifying.run(`chrome.notifications.create('mine', { type: 'basic', title: 't', message: 'm' })`), 'mine');
assert.equal(await notifying.run(`new Promise(done => chrome.notifications.create({ type: 'basic', title: 't', message: 'm' }, done))`), 'made-up-id');
assert.equal(notifying.run('nook.requests.filter(r => r.endsWith("notifications.create")).length'), 2);
notifying.run(`globalThis.clicks = []; chrome.notifications.onButtonClicked.addListener((id, index) => clicks.push(id + ' ' + index))`);
await pause(5);
notifying.run(`nook.post({ event: 'notifications.onButtonClicked', args: ['mine', 1] })`);
assert.equal(notifying.run('clicks.join()'), 'mine 1');

// identity: the redirect address is answered here and at once, as Chrome answers it.
const signing = load('chrome', 'extension', { permissions: ['identity'] });
assert.equal(signing.run(`[chrome.identity.getRedirectURL(), chrome.identity.getRedirectURL('cb'), chrome.identity.getRedirectURL('/cb')].join()`),
             'https://abc.chromiumapp.org/,https://abc.chromiumapp.org/cb,https://abc.chromiumapp.org/cb');
assert.equal(signing.run('nook.requests.length'), 0);
assert.equal(notifying.run('chrome.identity'), undefined);

// The offscreen document and the worker. WebKit joins neither to the other as a service worker client,
// so clients.matchAll() and postMessage in both directions run over one runtime port.
function portPair(name, sender) {
    const end = () => { const heard = []; return { name, sender, heard, onMessage: { addListener: f => heard.push(f) }, onDisconnect: { addListener() {} } }; };
    const a = end(), b = end();
    a.postMessage = m => { const copy = JSON.parse(JSON.stringify(m)); queueMicrotask(() => b.heard.forEach(f => f(copy))); };
    b.postMessage = m => { const copy = JSON.parse(JSON.stringify(m)); queueMicrotask(() => a.heard.forEach(f => f(copy))); };
    return [a, b];
}
const dom = { EventTarget, MessageEvent, MessageChannel };
const worker = load('chrome', 'extension', { permissions: ['offscreen'], globals: dom, before: `
  globalThis.registration = {};
  const target = new EventTarget();
  globalThis.dispatchEvent = e => target.dispatchEvent(e);
  globalThis.addEventListener = (type, f) => target.addEventListener(type, f);
  globalThis.clients = { matchAll: () => Promise.resolve([]), get: () => Promise.resolve(undefined) };` });
worker.run(`globalThis.ownPorts = []; chrome.runtime.onConnect.addListener(p => ownPorts.push(p.name));
  globalThis.heard = [];
  addEventListener('message', e => {
    heard.push(e.data);
    if (e.ports[0]) { e.ports[0].onmessage = m => heard.push('port ' + m.data); e.ports[0].postMessage('ping'); }
    e.source.postMessage('back');
  });`);
assert.equal((await worker.run('clients.matchAll()')).length, 0);
const connect = info => {
    const [mine, theirs] = portPair(info.name, { url: 'webkit-extension://abc/off.html' });
    queueMicrotask(() => worker.context.chrome.runtime.onConnect.fire(theirs));
    return mine;
};
const offscreenPage = load('chrome', 'extension', { permissions: ['offscreen'], globals: { ...dom, CONNECT: connect }, before: `
  globalThis.__nookOffscreen = true;
  globalThis.addEventListener = () => {};
  globalThis.nowhere = 0;
  globalThis.ServiceWorker = class ServiceWorker { postMessage() { nowhere++; } };
  class Container extends EventTarget { get controller() { return null; } getRegistration() { return Promise.resolve({ active: new ServiceWorker() }); } }
  navigator.serviceWorker = new Container();
  chrome.runtime.connect = CONNECT;` });
await new Promise(done => setTimeout(done, 10));
assert.equal(JSON.stringify((await worker.run('clients.matchAll()')).map(c => c.url + ' ' + c.type)), '["webkit-extension://abc/off.html window"]');
assert.equal((await worker.run(`clients.matchAll({ type: 'worker' })`)).length, 0);
assert.equal(offscreenPage.run('navigator.serviceWorker.controller instanceof ServiceWorker'), true);
offscreenPage.run(`globalThis.got = [];
  navigator.serviceWorker.addEventListener('message', e => got.push(e.data));
  globalThis.pipe = new MessageChannel();
  pipe.port1.onmessage = e => { got.push('port ' + e.data); pipe.port1.postMessage('pong'); };
  navigator.serviceWorker.getRegistration().then(r => r.active.postMessage('hello', [pipe.port2]));`);
await new Promise(done => setTimeout(done, 100));
assert.equal(worker.run('heard.join()'), 'hello,port pong');
assert.equal(offscreenPage.run('got.sort().join()'), 'back,port ping');
assert.equal(offscreenPage.run('nowhere'), 0);
// The link is the shim's own: the extension's onConnect listeners never see it.
assert.equal(worker.run('ownPorts.length'), 0);
// Any other page of the extension reaches the worker the same way, from its first post on. It is answered through
// the message's source, is not one of the worker's clients, and keeps the null controller WebKit gives it.
let pageLinks = 0;
const connectPage = info => { pageLinks++; const [mine, theirs] = portPair(info.name, { url: 'webkit-extension://abc/popup.html' });
                              queueMicrotask(() => worker.context.chrome.runtime.onConnect.fire(theirs)); return mine; };
const plainPage = load('chrome', 'extension', { permissions: ['offscreen'], globals: { ...dom, CONNECT: connectPage }, before: `
  globalThis.addEventListener = () => {};
  globalThis.nowhere = 0;
  globalThis.ServiceWorker = class ServiceWorker { postMessage() { nowhere++; } };
  class Container extends EventTarget { get controller() { return null; } getRegistration() { return Promise.resolve({ active: new ServiceWorker() }); } }
  navigator.serviceWorker = new Container();
  chrome.runtime.connect = CONNECT;` });
await pause(10);
assert.equal(pageLinks, 0);
worker.run('heard.length = 0');
plainPage.run(`globalThis.got = [];
  navigator.serviceWorker.addEventListener('message', e => got.push(e.data + ' from worker:' + (e.source instanceof ServiceWorker)));
  navigator.serviceWorker.getRegistration().then(r => { r.active.postMessage('from popup'); r.active.postMessage('again'); });`);
await pause(100);
assert.equal(worker.run('heard.join()'), 'from popup,again');
assert.equal(plainPage.run('got.join()'), 'back from worker:true,back from worker:true');
assert.equal(plainPage.run('nowhere + " " + navigator.serviceWorker.controller'), '0 null');
// A post from a page whose extension is gone throws nothing, as WebKit's own does not.
const orphan = load('chrome', 'extension', { permissions: ['offscreen'], globals: dom, before: `
  globalThis.addEventListener = () => {};
  globalThis.ServiceWorker = class ServiceWorker { postMessage() {} };
  class Container extends EventTarget { get controller() { return null; } getRegistration() { return Promise.resolve({ active: new ServiceWorker() }); } }
  navigator.serviceWorker = new Container();
  chrome.runtime.connect = () => { throw new Error('Extension context invalidated.'); };` });
assert.equal(orphan.run(`new ServiceWorker().postMessage('x')`), undefined);
assert.equal(pageLinks, 1);
assert.equal((await worker.run('clients.matchAll()')).length, 1);
assert.equal(worker.run('ownPorts.length'), 0);

// A content script's first message waits for the worker. WebKit answers a message with nothing while the worker has
// no listener yet, so the shim asks until the worker's shim answers, and only then sends what the extension sent.
const starting = load('chrome', 'content', { before: `
  globalThis.sent = [];
  globalThis.workerUpAfter = 2;
  chrome.runtime.sendMessage = function (m) {
    const ping = !!m && m.__nookCompatPing === 1, cb = typeof arguments[arguments.length - 1] === 'function' ? arguments[arguments.length - 1] : null;
    sent.push(ping ? 'ping' : m);
    const reply = Promise.resolve(ping ? (sent.filter(x => x === 'ping').length > workerUpAfter ? true : undefined) : 'reply:' + m);
    return cb ? void reply.then(cb) : reply;
  };` });
const first = starting.run(`Promise.all([chrome.runtime.sendMessage('a'), new Promise(done => chrome.runtime.sendMessage('b', done)), chrome.runtime.sendMessage('c')])`);
assert.equal(starting.run('sent.join()'), 'ping');
assert.equal((await first).join(), 'reply:a,reply:b,reply:c');
assert.equal(starting.run('sent.join()'), 'ping,ping,ping,a,b,c');
// Once the worker has answered, nothing more is asked.
assert.equal(await starting.run(`chrome.runtime.sendMessage('d')`), 'reply:d');
assert.equal(starting.run('sent.length'), 7);
// A worker that never answers is messaged all the same, once the wait has run out. The wait is by the clock:
// here each pause runs a hundred times faster and the clock a hundred times faster with it.
const fast = { setTimeout: (f, ms) => setTimeout(f, ms / 100), Date: { now: () => Date.now() * 100 } };
const stuck = load('chrome', 'content', { globals: fast, before: `
  globalThis.pings = 0;
  chrome.runtime.sendMessage = m => Promise.resolve(m && m.__nookCompatPing === 1 ? void pings++ : 'late:' + m);` });
assert.equal(await stuck.run(`chrome.runtime.sendMessage('x')`), 'late:x');
assert.ok(stuck.run('pings') >= 8 && stuck.run('pings') <= 20, 'the wait backs off: ' + stuck.run('pings'));
// A hidden page's timers run a second apart or worse. The wait still ends after its four seconds.
const hidden = load('chrome', 'content', { globals: { setTimeout: (f, ms) => setTimeout(f, 10), Date: { now: () => Date.now() * 100 } }, before: `
  globalThis.pings = 0;
  chrome.runtime.sendMessage = m => Promise.resolve(m && m.__nookCompatPing === 1 ? void pings++ : 'late:' + m);` });
assert.equal(await hidden.run(`chrome.runtime.sendMessage('x')`), 'late:x');
assert.ok(hidden.run('pings') <= 6, 'a throttled page asks a few times, not fourteen: ' + hidden.run('pings'));
// A background Nook could not put the shim in has nobody to answer, and its own listeners are never asked.
const alone = load('chrome', 'content', { backgroundShim: false, before: `globalThis.native = () => 'native'; chrome.runtime.sendMessage = native;` });
assert.equal(alone.run('chrome.runtime.sendMessage === native'), true);
// The worker's shim answers the question, and no listener of the extension's sees it, in the worker or in a page.
worker.run(`globalThis.messages = []; chrome.runtime.onMessage.addListener(m => { messages.push(m); });`);
assert.equal(worker.run(`globalThis.answers = []; chrome.runtime.onMessage.fire({ __nookCompatPing: 1 }, {}, a => answers.push(a)); answers.join() + ' ' + messages.length`), 'true 0');
worker.run(`chrome.runtime.onMessage.fire('real', {}, () => {})`);
assert.equal(worker.run('messages.join()'), 'real');
// An MV2 background page is the background too, and answers.
const mv2 = load('firefox', 'extension', { before: `globalThis.window = globalThis; chrome.extension = { getBackgroundPage: () => globalThis };` });
assert.equal(mv2.run(`globalThis.answers = []; chrome.runtime.onMessage.fire({ __nookCompatPing: 1 }, {}, a => answers.push(a)); answers.join()`), 'true');
// The extension is told of its own listeners only, not of the shim's.
assert.equal(mv2.run('chrome.runtime.onMessage.hasListeners()'), false);
assert.equal(mv2.run('chrome.runtime.onMessage.addListener(() => {}); chrome.runtime.onMessage.hasListeners()'), true);
plainPage.run(`globalThis.messages = []; chrome.runtime.onMessage.addListener(m => { messages.push(m); });`);
assert.equal(plainPage.run(`globalThis.answers = []; chrome.runtime.onMessage.fire({ __nookCompatPing: 1 }, {}, a => answers.push(a)); answers.length + ' ' + messages.length`), '0 0');
// A page of its own keeps sendMessage as WebKit made it: only a content script can be ahead of the worker.
const ownPage = load('chrome', 'extension', { before: `globalThis.native = () => 'native'; chrome.runtime.sendMessage = native;` });
assert.equal(ownPage.run('chrome.runtime.sendMessage === native'), true);

// A worker's import of a script that holds nothing is not made: WebKit would run the waiting microtasks after it,
// which Chrome does not, and Tampermonkey's startup depends on the difference.
const importing = load('chrome', 'extension', { empty: ['test.js', 'lib/blank file.js'], globals: { IMPORTED: [] },
                                                before: `globalThis.importScripts = (...urls) => { IMPORTED.push(urls.join('+')); };` });
importing.run(`importScripts('/test.js'); importScripts('test.js', './lib/blank%20file.js'); importScripts('/a.js', '/test.js', 'b.js');
  importScripts('https://cdn.test/test.js'); importScripts('/lib/test.js');`);
assert.equal(importing.context.IMPORTED.join(), '/a.js+b.js,https://cdn.test/test.js,/lib/test.js');
// With nothing listed, importScripts is WebKit's own.
const importingAll = load('chrome', 'extension', { before: `globalThis.native = () => {}; globalThis.importScripts = native;` });
assert.equal(importingAll.run('importScripts === native'), true);

console.log('extension compat shim: all checks passed');
// The relay's message ports stay open, and would keep the process alive.
process.exit(0);
