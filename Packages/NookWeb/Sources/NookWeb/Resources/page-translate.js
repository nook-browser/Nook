// Nook Translate
// Runs in the NookTranslate world, main frame only, installed on first use by PageSession+Translate.
// Text nodes get ids; Swift translates them and writes back. Originals stay here for Show Original.
(function () {
    if (window.__nookTranslate) { return; }

    const SKIP = 'script, style, noscript, template, code, pre, kbd, samp, textarea, input, select, svg, math, '
        + '[contenteditable]:not([contenteditable="false"]), [translate="no"], .notranslate';
    const SAMPLE_LIMIT = 2048;
    const FLUSH_DELAY = 300;

    let originals = new Map(); // id -> { node, text }
    let tracked = new WeakSet();
    let nextID = 0;
    let observer = null;
    let pendingRoots = [];
    let flushScheduled = false;

    function walk(root, visit) {
        if (root.nodeType === Node.TEXT_NODE) {
            if (!root.parentElement || root.parentElement.closest(SKIP)) { return; }
            visit(root);
            return;
        }
        if (root.nodeType !== Node.ELEMENT_NODE || root.closest(SKIP)) { return; }
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
            acceptNode(node) {
                if (node.nodeType === Node.ELEMENT_NODE) {
                    return node.matches(SKIP) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_SKIP;
                }
                return NodeFilter.FILTER_ACCEPT;
            }
        });
        let node;
        while ((node = walker.nextNode())) {
            if (visit(node) === false) { return; }
        }
    }

    // Untracked text nodes under root, as { id, text } with surrounding whitespace removed.
    function collect(root) {
        const out = [];
        walk(root, (node) => {
            if (tracked.has(node)) { return; }
            const text = node.nodeValue;
            const trimmed = text.trim();
            if (!trimmed || !/\p{L}/u.test(trimmed)) { return; }
            const id = String(nextID++);
            tracked.add(node);
            originals.set(id, { node: node, text: text });
            out.push({ id: id, text: trimmed });
        });
        return out;
    }

    function flush() {
        flushScheduled = false;
        const roots = pendingRoots;
        pendingRoots = [];
        const nodes = [];
        for (const root of roots) {
            if (root.isConnected) { nodes.push(...collect(root)); }
        }
        if (nodes.length) {
            window.webkit.messageHandlers.nookTranslate.postMessage({ nodes: nodes });
        }
    }

    function observe() {
        if (observer) { return; }
        observer = new MutationObserver((records) => {
            for (const record of records) {
                for (const node of record.addedNodes) { pendingRoots.push(node); }
            }
            if (pendingRoots.length && !flushScheduled) {
                flushScheduled = true;
                setTimeout(flush, FLUSH_DELAY);
            }
        });
        observer.observe(document.body || document.documentElement, { childList: true, subtree: true });
    }

    window.__nookTranslate = {
        // About 2 KB of the page's text and its declared language, for detection.
        sample() {
            let text = '';
            if (document.body) {
                walk(document.body, (node) => {
                    const trimmed = node.nodeValue.trim();
                    if (trimmed) { text += trimmed + ' '; }
                    return text.length < SAMPLE_LIMIT;
                });
            }
            return { text: text.slice(0, SAMPLE_LIMIT), lang: document.documentElement.lang || '' };
        },

        // Starts translating: returns the text nodes not yet sent and watches for new ones.
        start() {
            observe();
            return document.body ? collect(document.body) : [];
        },

        // pairs: [[id, translatedText]]. Keeps the original's leading and trailing whitespace.
        apply(pairs) {
            for (const [id, translated] of pairs) {
                const entry = originals.get(id);
                if (!entry || !entry.node.isConnected) { continue; }
                const lead = entry.text.match(/^\s*/)[0];
                const trail = entry.text.match(/\s*$/)[0];
                entry.node.nodeValue = lead + translated + trail;
            }
        },

        restore() {
            if (observer) { observer.disconnect(); observer = null; }
            pendingRoots = [];
            for (const entry of originals.values()) { entry.node.nodeValue = entry.text; }
            originals = new Map();
            tracked = new WeakSet();
        }
    };
})();
