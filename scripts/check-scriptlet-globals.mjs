// uBO's scriptlets read globals its own injector defines. One Nook's wrapper lacks throws
// inside the crate's per-scriptlet try/catch, so the scriptlet silently does nothing.
//   node scripts/check-scriptlet-globals.mjs
import { readFileSync, readdirSync } from 'fs';
import assert from 'assert';

const root = new URL('..', import.meta.url).pathname;
const dir = root + 'Packages/NookBlocker/ThirdParty/ubo-scriptlets/src/js/resources/';
const wrapper = readFileSync(root + 'Packages/NookBlocker/Sources/NookBlocker/AdvancedRulesEngine.swift', 'utf8');

const expected = new Set();
for (const file of readdirSync(dir).filter(f => f.endsWith('.js'))) {
  for (const m of readFileSync(dir + file, 'utf8').matchAll(/\/\*\s*globals?\s+([^*]+)\*\//g)) {
    m[1].split(/[\s,]+/).filter(Boolean).forEach(name => expected.add(name.split(':')[0]));
  }
}
assert(expected.has('scriptletGlobals'), 'expected the library to declare scriptletGlobals');
for (const name of expected) {
  assert(wrapper.includes(`const ${name}=`), `configUserScript must define ${name} around the scriptlets`);
}
console.log(`scriptlet globals ok: ${[...expected].join(', ')}`);
