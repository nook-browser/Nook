// Generates Packages/NookBlocker/Sources/NookBlocker/Resources/scriptlets.json
// from the vendored uBlock Origin resources. Run after refreshing the pin:
//   node scripts/build-scriptlets.mjs
//
// uBO registers each scriptlet with its name, aliases, dependencies and trust
// requirement, and resolves dependency function references to names as it goes.
// Importing the modules and reading that registry is exact, where parsing the
// source would be guesswork. The body of a resource is the function's own
// source text, which is the form adblock-rust injects.
import { readdirSync, readFileSync, writeFileSync } from 'fs';
import { fileURLToPath } from 'url';
import path from 'path';

const root = path.dirname(fileURLToPath(new URL('.', import.meta.url)));
const uboSrc = path.join(root, 'Packages/NookBlocker/ThirdParty/ubo-scriptlets/src');
const resourceDir = path.join(uboSrc, 'js/resources');
const out = path.join(root, 'Packages/NookBlocker/Sources/NookBlocker/Resources/scriptlets.json');

const { registeredScriptlets } = await import(path.join(resourceDir, 'base.js'));
for (const file of readdirSync(resourceDir).filter(f => f.endsWith('.js') && f !== 'base.js')) {
    await import(path.join(resourceDir, file));
}

const namedDeclaration = /^\s*(async\s+)?function\s+[A-Za-z_$]/;
const entries = [];
for (const s of registeredScriptlets) {
    const body = s.fn.toString();
    const isDependency = s.name.endsWith('.fn');
    // adblock-rust emits `name(args)` for an injectable resource, so its body has
    // to be a declaration it can call. A dependency is inlined verbatim, so the
    // three that are classes are fine there.
    if (!isDependency && !namedDeclaration.test(body)) {
        throw new Error(`${s.name} is injectable but not a named function declaration`);
    }
    entries.push({
        name: s.name,
        aliases: s.aliases ?? [],
        kind: { mime: isDependency ? 'fn/javascript' : 'application/javascript' },
        content: Buffer.from(body, 'utf8').toString('base64'),
        dependencies: s.dependencies ?? [],
        ...(s.requiresTrust ? { permission: 1 } : {}),
    });
}

// uBO's redirect resources double as argument-less scriptlets: `##+js(noeval)`
// and friends. They are whole scripts rather than callable functions, which
// adblock-rust injects verbatim, so the declaration rule above does not apply.
// Only the `data: 'text'` ones can be injected; the rest exist for $redirect,
// which WebKit's rule lists cannot do anyway.
const MIME = { '.js': 'application/javascript', '.html': 'text/html', '.css': 'text/css',
               '.json': 'application/json', '.xml': 'text/xml', '.txt': 'text/plain' };
const redirects = (await import(path.join(uboSrc, 'js/redirect-resources.js'))).default;
for (const [name, details] of redirects) {
    if (details.data !== 'text') { continue; }
    // `empty` has no extension: it is a zero-byte stand-in for any text type.
    const mime = path.extname(name) === '' ? 'text/plain' : MIME[path.extname(name)];
    if (!mime) { throw new Error(`no mime for redirect resource ${name}`); }
    if (entries.some(e => e.name === name)) { continue; }
    entries.push({
        name,
        aliases: details.alias ? [details.alias].flat() : [],
        kind: { mime },
        content: readFileSync(path.join(uboSrc, 'web_accessible_resources', name)).toString('base64'),
        dependencies: [],
    });
}

entries.sort((a, b) => a.name.localeCompare(b.name));
writeFileSync(out, JSON.stringify(entries));
const deps = entries.filter(e => e.kind.mime === 'fn/javascript').length;
console.log(`${entries.length} resources (${entries.length - deps} injectable, ${deps} dependency-only, ` +
            `${entries.filter(e => e.permission).length} trusted) -> ${path.relative(root, out)}`);
