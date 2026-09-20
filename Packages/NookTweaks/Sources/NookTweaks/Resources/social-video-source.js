// Runs at document start in the page's world, because React's data is only visible here.
// Facebook and Instagram play video through MSE blob: URLs, so the saveable MP4 (with audio) lives in
// React props: browser_native_hd_url / playable_url on Facebook, video_versions on Instagram.
// social-image-download.js dispatches 'nook-social-video-url' on a <video>; this answers synchronously
// in the element's data-nook-video-url attribute. It reads data only. The app does not check the host:
// it takes any https URL, sends cookies only to the page's own site, and keeps only an image or video.
(function () {
    if (!/(^|\.)(instagram\.com|facebook\.com)$/.test(location.hostname)) return;

    const MP4 = /^https:\/\/[^/?#]*(cdninstagram\.com|fbcdn\.net)\/[^?#]*\.mp4/;
    const MAX_LEVELS = 40, MAX_DEPTH = 6, MAX_NODES = 20000;

    function collect(value, key, parent, depth, seen, out) {
        if (typeof value === 'string') {
            if (MP4.test(value)) out.push({ url: value, key, parent });
            return;
        }
        if (!value || typeof value !== 'object' || depth === 0 || seen.has(value) || seen.size > MAX_NODES) return;
        // React elements carry other components' props (other stories); DOM nodes are not data.
        if (value.$$typeof || value instanceof Node) return;
        seen.add(value);
        let keys;
        try { keys = Object.keys(value); } catch { return; }
        for (const k of keys) {
            if (k.startsWith('_')) continue;   // Relay store internals hold every video on the page
            let v;
            try { v = value[k]; } catch { continue; }
            collect(v, k, value, depth - 1, seen, out);
        }
    }

    // Facebook: browser_native_hd_url / playable_url_quality_hd, or progressive_urls[].metadata.quality.
    // Instagram: video_versions[] with width and height.
    function score({ key, parent }) {
        const area = (+parent?.width || 0) * (+parent?.height || 0) || 1;
        const name = `${key} ${parent?.metadata?.quality ?? ''}`.toLowerCase();
        return area * (name.includes('hd') ? 4 : name.includes('sd') ? 1 : 2);
    }

    // Instagram links DOM nodes to fibers with expando keys. Facebook's React keeps that map private, and its
    // player creates the <video> outside React anyway; only the root container is marked. From there, walk
    // down, skipping every host subtree that does not contain the element, to the deepest fiber that does.
    const MAX_FIBERS = 50000;
    function fiberOf(element) {
        let container = null;
        for (let node = element; node; node = node.parentElement) {
            const keys = Object.keys(node);
            const fiberKey = keys.find(k => k.startsWith('__reactFiber$'));
            if (fiberKey) return node[fiberKey];
            const containerKey = !container && keys.find(k => k.startsWith('__reactContainer$'));
            if (containerKey) container = node[containerKey];
        }
        const stack = container?.stateNode?.current ? [container.stateNode.current] : [];
        let found = null, foundNode = null, visited = 0;
        while (stack.length && visited++ < MAX_FIBERS) {
            const fiber = stack.pop();
            const node = fiber.tag === 4 ? fiber.stateNode?.containerInfo : fiber.stateNode;   // 4: portal
            if (node instanceof Element) {
                if (!node.contains(element)) continue;
                if (fiber.tag !== 4 && (!foundNode || foundNode.contains(node))) { found = fiber; foundNode = node; }
            }
            for (let child = fiber.child; child; child = child.sibling) stack.push(child);
        }
        return found;
    }

    // Relay components get fragment references as props and read the data in hooks, so check both.
    function collectFiber(fiber, seen, out) {
        collect(fiber.memoizedProps, '', null, MAX_DEPTH, seen, out);
        if (fiber.tag === 1) return collect(fiber.memoizedState, '', null, MAX_DEPTH, seen, out);   // 1: class
        for (let hook = fiber.memoizedState, i = 0; hook && typeof hook === 'object' && i < 50; hook = hook.next, i++) {
            collect(hook.memoizedState, '', null, MAX_DEPTH, seen, out);
        }
    }

    document.addEventListener('nook-social-video-url', event => {
        const video = event.target;
        const seen = new Set();
        let fiber = fiberOf(video), best = null, level = 0;
        // The nearest component with a video URL owns this <video>; stop there.
        for (; fiber && level < MAX_LEVELS && !best; level++, fiber = fiber.return) {
            const found = [];
            collectFiber(fiber, seen, found);
            for (const candidate of found) if (!best || score(candidate) > score(best)) best = candidate;
        }
        if (!best) return;
        const size = best.parent?.width ? ` ${best.parent.width}x${best.parent.height}` : '';
        video.setAttribute('data-nook-video-url', JSON.stringify({ url: best.url, note: `${best.key}${size} level ${level - 1}` }));
    }, true);
})();
