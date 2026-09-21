// Checks the generated redirect table and the in-page matcher that consumes it.
//   node scripts/check-redirects.mjs
import { readFileSync } from 'fs';
import assert from 'assert';
import vm from 'vm';

const root = new URL('..', import.meta.url).pathname;
const res = root + 'Packages/NookBlocker/Sources/NookBlocker/Resources/';
const { rules, bodies } = JSON.parse(readFileSync(res + 'redirects.json', 'utf8'));

// Patterns must mean what the filter syntax says. `||host^` covers the host and
// its subdomains and stops at a separator, so it must not match a lookalike.
const hit = (url, pred) => rules.some(r => pred(r) && new RegExp(r.p).test(url));
assert(hit('https://imasdk.googleapis.com/js/sdkloader/ima3.js', r => r.r === 'google-ima.js'),
  'the ima3 loader must map to the ima shim');
const syndication = rules.filter(r => r.p.includes('googlesyndication'));
assert(syndication.length > 0, 'expected a googlesyndication redirect rule');
assert(syndication.some(r => new RegExp(r.p).test('https://sub.googlesyndication.com/x.js')),
  '|| must reach subdomains');
assert(!syndication.some(r => new RegExp(r.p).test('https://notgooglesyndication.com/x.js')),
  '|| must not match a host that merely ends with the name');

// `redirect-rule=` only fires on requests that are blocked anyway, which the
// page cannot know. `*$script,redirect-rule=noopjs` compiles to `.*`, so taking
// one at face value empties every script on the page.
assert(!rules.some(r => new RegExp(r.p).test('https://unrelated.example/app.js') && !r.d),
  'no global rule may match an arbitrary script URL');
assert(Object.values(bodies).every(b => b.startsWith('data:')), 'bodies must be data: URLs');
assert(!rules.some(r => /html-load|ad-shield/i.test(r.p)),
  'Ad-Shield validates its payload and must never be answered');

// The matcher itself, against a table shaped like the one Swift emits.
const table = [
  ['^https?://([^/?#]+\\.)?ads\\.example\\.com/gpt\\.js', bodies[Object.keys(bodies)[0]], ['script']],
  ['^https?://([^/?#]+\\.)?pix\\.example\\.com/p\\.gif', 'data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==', ['image']],
];
const sandbox = {
  window: { __nookRedirects: table },
  document: { baseURI: 'https://site.example/' },
  URL, RegExp, Array, Object, atob: s => Buffer.from(s, 'base64').toString('binary'),
  decodeURIComponent, Response: class {}, XMLHttpRequest: function () {},
  HTMLScriptElement: function () {}, HTMLImageElement: function () {}, Element: function () {},
};
sandbox.XMLHttpRequest.prototype = { open() {}, send() {} };
sandbox.Element.prototype = { setAttribute() {} };
vm.createContext(sandbox);
// Expose the private matcher for the check without altering the shipped file.
const src = readFileSync(res + 'nook-stealth-redirects.js', 'utf8')
  .replace('})();', '  window.__test = { bodyFor, decode };\n})();');
vm.runInContext(src, sandbox);
const { bodyFor, decode } = sandbox.window.__test;

assert.strictEqual(bodyFor('https://ads.example.com/gpt.js', 'script'), table[0][1], 'script rule must fire');
assert.strictEqual(bodyFor('https://ads.example.com/gpt.js', 'image'), null, 'request type must be honoured');
assert.strictEqual(bodyFor('https://unrelated.example/app.js', 'script'), null, 'unrelated URL must pass through');
assert.strictEqual(bodyFor('data:text/html,x', 'script'), null, 'non-http schemes are not ours');
assert.strictEqual(decode(table[1][1]).mime, 'image/gif', 'mime must survive the round trip');
assert(decode(table[0][1]).text.length > 0, 'a real shim must decode to a body');

console.log(`${rules.length} rules, ${Object.keys(bodies).length} bodies, all redirect checks passed`);
