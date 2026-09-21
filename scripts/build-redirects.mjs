// Generates Packages/NookBlocker/Sources/NookBlocker/Resources/redirects.json
// from the $redirect= and $redirect-rule= network rules in the bundled filter
// lists, paired with uBlock Origin's redirect resource bodies.
//
// WebKit's content rule lists can block a request but cannot answer one, so the
// substitution happens in the page, in nook-stealth-redirects.js. The table it
// needs is built per navigation by AdvancedRulesEngine, because most of these
// rules are domain-scoped and a given page needs only a handful of them.
//
//   node scripts/build-redirects.mjs
import { readdirSync, readFileSync, writeFileSync } from 'fs';
import { fileURLToPath } from 'url';
import path from 'path';

const root = path.dirname(fileURLToPath(new URL('.', import.meta.url)));
const uboSrc = path.join(root, 'Packages/NookBlocker/ThirdParty/ubo-scriptlets/src');
const listDir = path.join(root, 'Packages/NookBlocker/Sources/NookBlocker/Resources');
const out = path.join(listDir, 'redirects.json');

// Ad-Shield compares the script it receives against an X-Length response header,
// so a body with no headers reads as malformed and it replaces the document with
// an error modal. Blocking it outright is the milder failure. See CLAUDE.md.
const NEVER_ANSWER = /html-load\.|ad-shield|adshield/i;

const MIME = {
    '.js': 'application/javascript', '.html': 'text/html', '.css': 'text/css',
    '.json': 'application/json', '.xml': 'text/xml', '.txt': 'text/plain',
    '.gif': 'image/gif', '.png': 'image/png', '.mp3': 'audio/mpeg', '.mp4': 'video/mp4',
    '': 'text/plain',
};

const redirectResources = (await import(path.join(uboSrc, 'js/redirect-resources.js'))).default;
const canonical = new Map();
for (const [name, details] of redirectResources) {
    canonical.set(name, name);
    for (const alias of [details.alias ?? []].flat()) { canonical.set(alias, name); }
}

// uBO/ABP pattern grammar. `||` anchors to a domain and its subdomains, `^` is a
// separator, `|` anchors an end, `*` is a wildcard, and /slashes/ mean a literal
// regex. Everything else is a literal.
function patternToRegex(pattern) {
    if (pattern.length > 2 && pattern.startsWith('/') && pattern.endsWith('/')) {
        return pattern.slice(1, -1);
    }
    let rest = pattern;
    let source = '';
    if (rest.startsWith('||')) { source = '^https?://([^/?#]+\\.)?'; rest = rest.slice(2); }
    else if (rest.startsWith('|')) { source = '^'; rest = rest.slice(1); }
    let tail = '';
    if (rest.endsWith('|')) { rest = rest.slice(0, -1); tail = '$'; }
    for (const ch of rest) {
        if (ch === '*') { source += '.*'; }
        else if (ch === '^') { source += '(?:[/?#&=:;,]|$)'; }
        else { source += ch.replace(/[.*+?^${}()|[\]\\]/, m => '\\' + m); }
    }
    return source + tail;
}

const TYPE_OPTIONS = new Set(['script', 'xhr', 'xmlhttprequest', 'image', 'media', 'subdocument',
                              'stylesheet', 'font', 'object', 'other', 'ping', 'beacon']);

const rules = [];
const usedResources = new Set();
let skippedUnknown = 0, skippedNever = 0, skippedConditional = 0, skippedBroad = 0;

for (const file of readdirSync(listDir).filter(f => f.endsWith('.txt'))) {
    for (const raw of readFileSync(path.join(listDir, file), 'utf8').split('\n')) {
        const line = raw.trim();
        if (line === '' || line.startsWith('!') || line.startsWith('@@')) { continue; }
        if (line.includes('##') || line.includes('#@#')) { continue; }
        const dollar = line.lastIndexOf('$');
        if (dollar < 0) { continue; }
        const pattern = line.slice(0, dollar);
        const options = line.slice(dollar + 1).split(',');
        // `redirect-rule=` only applies when the request would be blocked anyway,
        // and the page cannot know that. Taken at face value it is catastrophic:
        // `*$script,redirect-rule=noopjs` compiles to `.*` and empties every
        // script on the page. Only unconditional `redirect=` rules are safe here.
        if (options.some(o => o.startsWith('redirect-rule='))) { skippedConditional++; continue; }
        const redirect = options.find(o => o.startsWith('redirect='));
        if (!redirect) { continue; }

        // `resource:priority` — the priority only orders competing rules, which
        // does not arise here because the first match in a page's table wins.
        const target = redirect.slice(redirect.indexOf('=') + 1).split(':')[0];
        if (target === 'none' || target === '') { continue; }
        const resource = canonical.get(target) ?? canonical.get(target + '.js');
        if (!resource) { skippedUnknown++; continue; }
        if (NEVER_ANSWER.test(pattern)) { skippedNever++; continue; }

        const domainOpt = options.find(o => o.startsWith('domain='));
        const domains = [], excluded = [];
        for (const d of domainOpt ? domainOpt.slice(7).split('|') : []) {
            if (d.startsWith('~')) { excluded.push(d.slice(1)); } else if (d) { domains.push(d); }
        }
        const types = options.filter(o => TYPE_OPTIONS.has(o))
            .map(o => o === 'xmlhttprequest' ? 'xhr' : o === 'beacon' ? 'ping' : o);

        // A pattern with almost no literal text matches half the web. Nothing in
        // the lists should produce one, so refuse rather than ship it.
        const literal = patternToRegex(pattern).replace(/\\(.)/g, '$1')
            .replace(/\(\?:[^)]*\)|\[[^\]]*\]|[.*+?^${}()|]/g, '');
        if (literal.length < 6) { skippedBroad++; continue; }

        usedResources.add(resource);
        rules.push({
            p: patternToRegex(pattern),
            r: resource,
            ...(domains.length ? { d: domains } : {}),
            ...(excluded.length ? { x: excluded } : {}),
            ...(types.length ? { t: types } : {}),
        });
    }
}

const bodies = {};
for (const name of usedResources) {
    const file = path.join(uboSrc, 'web_accessible_resources', name);
    const mime = MIME[path.extname(name)];
    if (!mime) { throw new Error(`no mime for redirect resource ${name}`); }
    // A data: URL so the page can hand it straight to src or to a Response. The
    // per-page table carries only the few a page's rules actually name.
    bodies[name] = `data:${mime};base64,${readFileSync(file).toString('base64')}`;
}

// A regex that will not compile in JavaScriptCore is worse than a missing rule.
for (const rule of rules) { new RegExp(rule.p); }

writeFileSync(out, JSON.stringify({ rules, bodies }));
const global = rules.filter(r => !r.d).length;
console.log(`${rules.length} redirect rules (${global} global, ${rules.length - global} domain-scoped), ` +
            `${usedResources.size} resources, ${(JSON.stringify(bodies).length / 1024).toFixed(0)}KB of bodies ` +
            `-> ${path.relative(root, out)}`);
console.log(`skipped: ${skippedConditional} redirect-rule, ${skippedBroad} too broad, ` +
            `${skippedUnknown} unknown target, ${skippedNever} never-answer`);
