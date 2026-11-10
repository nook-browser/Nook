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
  if (KIND === 'extension') Object.assign(chrome, {
    scripting: {}, tabs: {}, webNavigation: {}, action: {},
    permissions: { contains(query) {
      for (const p of query.permissions || []) if (p !== 'tabs') throw invalid('permissions.contains', "The 'permissions' value is invalid, because '" + p + "' is not a valid permission.");
      return Promise.resolve(true);
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

function load(identity, kind = 'extension') {
    const context = vm.createContext({ KIND: kind, location: { protocol: kind === 'extension' ? 'webkit-extension:' : 'https:' },
                                       setTimeout, clearTimeout, console: { warn() {} } });
    vm.runInContext(webkit, context);
    vm.runInContext(shim.replace('__NOOK_IDENTITY__', identity), context);
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

console.log('extension compat shim: all checks passed');
