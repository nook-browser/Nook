// Generates Nook/Managers/ExtensionManager/NookExtensionCompat.js: the shim in
// scripts/extension-compat/shim.js with its API tables filled in.
//   node scripts/build-extension-compat.mjs [path/to/chrome-types/index.d.ts]
//
// The tables are enum values, event names and the member names of the stubbed
// namespaces. They are read from chrome-types, the typings Google generates from
// Chromium's extension API definitions (Apache-2.0, github.com/GoogleChrome/chrome-types).
// Only names and enum strings are taken, no code. The file is pinned by hash: to
// move the pin, change VERSION and SHA256 together and read the diff of the output.
// Without a path argument the pinned file is fetched from unpkg.
import { createHash } from 'crypto';
import { readFileSync, writeFileSync } from 'fs';
import { fileURLToPath } from 'url';
import path from 'path';

const VERSION = '0.1.463';
const SHA256 = '32b467a9bb3463d8fce8ebcecb69070a17496a50eee7285c689204b60d1e676c';
// What a store build is told it runs in. Move these with the pin.
const CHROME_MAJOR = '157';
const FIREFOX_MAJOR = '145';

// Namespaces WebKit has. Enums and events Chrome defines in them are added where WebKit lacks them,
// and for a Chrome or Edge build its functions too.
const FILL = ['action', 'alarms', 'commands', 'contextMenus', 'cookies', 'declarativeNetRequest', 'dom', 'extension', 'i18n',
              'permissions', 'runtime', 'scripting', 'storage', 'tabs', 'webNavigation', 'webRequest', 'windows'];
// Namespaces WebKit lacks whose absence stops a background script while it starts. Each is a plain
// object with every member Chrome defines. A namespace is listed only with a measured failure behind it.
const STUB = ['management', 'notifications', 'privacy'];
// Namespaces `ExtensionCompatBridge` answers natively, with the manifest permission each needs. Keep
// in step with `ExtensionCompatPatcher.bridgedPermissions`. `extra` names functions the typings leave out.
const BRIDGED = {
    offscreen: { permission: 'offscreen', extra: ['hasDocument'] },
    idle: { permission: 'idle', extra: [] },
    notifications: { permission: 'notifications', extra: [] },
    management: { permission: 'management', extra: [] },
    identity: { permission: 'identity', extra: [] },
    sidePanel: { permission: 'sidePanel', extra: ['close', 'getLayout'] },
};
// Events Nook fires in a namespace WebKit has, each with the permission it needs.
const BRIDGED_EVENTS = {
    'webNavigation.onHistoryStateUpdated': 'webNavigation',
    'webNavigation.onReferenceFragmentUpdated': 'webNavigation',
};

const root = path.dirname(fileURLToPath(new URL('.', import.meta.url)));
const template = path.join(root, 'scripts/extension-compat/shim.js');
const out = path.join(root, 'Nook/Managers/ExtensionManager/NookExtensionCompat.js');

const source = process.argv[2]
    ? readFileSync(process.argv[2])
    : Buffer.from(await (await fetch(`https://unpkg.com/chrome-types@${VERSION}/index.d.ts`)).arrayBuffer());
const digest = createHash('sha256').update(source).digest('hex');
if (digest !== SHA256) { throw new Error(`chrome-types ${VERSION} expected, got a file with sha256 ${digest}`); }
const lines = source.toString('utf8').split('\n');

// One `declare namespace <name>` block: per API namespace, its functions, events, string enums and setting groups.
function block(name) {
    const start = lines.findIndex(l => l.startsWith(`declare namespace ${name} `));
    if (start < 0) { throw new Error(`no ${name} namespace in the typings`); }
    const found = {};
    let ns = null;
    for (let i = start + 1; i < lines.length; i++) {
        const line = lines[i];
        if (line.startsWith('declare namespace') || line === '}') { break; }
        const opened = /^  export namespace ([\w.]+) \{/.exec(line);
        if (opened) { ns = found[opened[1]] = { functions: new Set(), events: new Set(), enums: {}, settings: {} }; continue; }
        if (line === '  }') { ns = null; continue; }
        const member = ns && /^    export (function|const|type) ([A-Za-z_$][\w$]*)/.exec(line);
        if (!member) { continue; }
        const [, kind, id] = member;
        if (kind === 'function') {
            ns.functions.add(id);
        } else if (kind === 'const' && /^on[A-Z]/.test(id)) {
            ns.events.add(id);
        } else if (kind === 'const' && line.endsWith('{')) {
            // An object of settings, as in privacy.network.
            const group = {};
            for (let j = i + 1; j < lines.length && !lines[j].startsWith('    }'); j++) {
                const setting = /^      (\w+): types\.ChromeSetting<(\w+)>/.exec(lines[j]);
                if (setting) { group[setting[1]] = setting[2]; }
            }
            if (Object.keys(group).length) { ns.settings[id] = group; }
        } else if (kind === 'type') {
            let body = line;
            for (let j = i; !body.includes(';') && j - i < 60; ) { body += lines[++j]; }
            body = body.slice(body.indexOf('=') + 1);
            // A union of string literals is an enum, which Chrome also exposes as an object at run time.
            if (body.includes('"') && /^[\s|"\w.\-/+:;]+$/.test(body)) {
                ns.enums[id] = [...body.matchAll(/"([^"]+)"/g)].map(m => m[1]);
            }
        }
    }
    return found;
}

// `chrome` aliases what it shares with `browser`, so a namespace is the union of the two blocks.
const blocks = [block('browser'), block('chrome')];
function namespace(name) {
    const parts = blocks.map(b => b[name]).filter(Boolean);
    if (!parts.length) { throw new Error(`chrome-types ${VERSION} has no ${name} namespace`); }
    return {
        functions: [...new Set(parts.flatMap(p => [...p.functions]))].sort(),
        events: [...new Set(parts.flatMap(p => [...p.events]))].sort(),
        enums: Object.assign({}, ...parts.map(p => p.enums)),
        settings: Object.assign({}, ...parts.map(p => p.settings)),
    };
}

// Chrome's key for an enum value: upgradeScheme is UPGRADE_SCHEME, x86-64 is X86_64.
const enumKey = v => v.replace(/([a-z0-9])([A-Z])/g, '$1_$2').replace(/[^A-Za-z0-9]/g, '_').toUpperCase();
const enumObject = values => Object.fromEntries(values.map(v => [enumKey(v), v]));
const enumObjects = enums => Object.fromEntries(Object.keys(enums).sort().map(n => [n, enumObject(enums[n])]));

const tables = { enums: {}, events: [], functions: [], stubs: {}, bridged: {}, bridgedEvents: BRIDGED_EVENTS };
for (const name of FILL) {
    const ns = namespace(name);
    for (const [id, object] of Object.entries(enumObjects(ns.enums))) { tables.enums[`${name}.${id}`] = object; }
    tables.events.push(...ns.events.map(e => `${name}.${e}`));
    tables.functions.push(...ns.functions.map(f => `${name}.${f}`));
}
for (const name of STUB) {
    const ns = namespace(name);
    const settings = {};
    for (const [group, entries] of Object.entries(ns.settings)) {
        // A setting nobody can change reads as off, or as the first value of its enum.
        settings[group] = Object.fromEntries(Object.entries(entries).map(([id, type]) =>
            [id, type === 'boolean' ? false : (ns.enums[type] ?? [null])[0]]));
    }
    tables.stubs[name] = { functions: ns.functions, events: ns.events, enums: enumObjects(ns.enums), settings };
}

for (const [name, { permission, extra }] of Object.entries(BRIDGED)) {
    const ns = namespace(name);
    tables.bridged[name] = { permission, functions: [...new Set([...ns.functions, ...extra])].sort(),
                             events: ns.events, enums: enumObjects(ns.enums) };
}

// The pin moving under the shim should fail here, not in someone's extension.
const expect = (ok, what) => { if (!ok) { throw new Error(`tables look wrong: ${what}`); } };
expect(tables.enums['runtime.OnInstalledReason']?.INSTALL === 'install', 'runtime.OnInstalledReason');
expect(tables.enums['scripting.ExecutionWorld']?.ISOLATED === 'ISOLATED', 'scripting.ExecutionWorld');
expect(tables.enums['declarativeNetRequest.RuleActionType']?.UPGRADE_SCHEME === 'upgradeScheme', 'RuleActionType key rule');
expect(tables.events.includes('runtime.onUpdateAvailable'), 'runtime.onUpdateAvailable');
expect(tables.events.includes('webNavigation.onHistoryStateUpdated'), 'webNavigation.onHistoryStateUpdated');
expect(tables.functions.includes('action.getUserSettings'), 'action.getUserSettings');
expect(tables.stubs.notifications.events.includes('onClicked'), 'notifications.onClicked');
expect(tables.stubs.management.functions.includes('getSelf'), 'management.getSelf');
expect(tables.stubs.privacy.settings.services?.passwordSavingEnabled === false, 'privacy.services');
expect(tables.stubs.privacy.settings.network?.webRTCIPHandlingPolicy === 'default', 'privacy.network');

let shim = readFileSync(template, 'utf8');
expect(tables.bridged.offscreen.functions.includes('createDocument'), 'offscreen.createDocument');
expect(tables.bridged.idle.functions.includes('queryState') && tables.bridged.idle.events.includes('onStateChanged'), 'idle');
expect(tables.bridged.notifications.functions.includes('create') && tables.bridged.notifications.events.includes('onButtonClicked'), 'notifications');
expect(tables.bridged.management.functions.includes('getAll') && tables.bridged.management.events.includes('onDisabled'), 'management');
expect(tables.bridged.identity.functions.includes('launchWebAuthFlow') && tables.bridged.identity.functions.includes('getRedirectURL'), 'identity');
expect(tables.bridged.sidePanel.functions.includes('setPanelBehavior') && tables.bridged.sidePanel.functions.includes('open'), 'sidePanel');
for (const event of Object.keys(BRIDGED_EVENTS)) { expect(tables.events.includes(event), event); }
for (const token of ['__NOOK_TABLES__', '__NOOK_IDENTITY__', '__NOOK_OWNS_CHANNEL__', '__NOOK_BACKGROUND_SHIM__', "'__NOOK_EMPTY_SCRIPTS__'", '__CHROME_MAJOR__', '__FIREFOX_MAJOR__']) {
    expect(shim.includes(token), `${token} in the template`);
}
const header = `// Nook extension compatibility shim: runs first in every context of a store-built extension.\n` +
    `// Generated by scripts/build-extension-compat.mjs from scripts/extension-compat/shim.js. Do not edit.\n` +
    `// API tables from chrome-types ${VERSION} (Copyright Google LLC, Apache-2.0).\n`;
shim = header + shim.split('\n').slice(2).join('\n')
    .replace('__NOOK_TABLES__', () => JSON.stringify(tables))
    .replaceAll('__CHROME_MAJOR__', CHROME_MAJOR)
    .replaceAll('__FIREFOX_MAJOR__', FIREFOX_MAJOR);
// Parses the result without running it.
new Function(shim);
writeFileSync(out, shim);
console.log(`${Object.keys(tables.enums).length} enums, ${tables.events.length} events, ${tables.functions.length} functions, ` +
            `${STUB.length} stubbed and ${Object.keys(BRIDGED).length} bridged namespaces, ${shim.length} bytes -> ${path.relative(root, out)}`);
