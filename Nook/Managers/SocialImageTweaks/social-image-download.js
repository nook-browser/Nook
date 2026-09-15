// Runs at document start in the main frame, in its own content world.
// Shows a download button over the photo or video under the pointer on Instagram, Facebook, and VSCO.
// Both sites obfuscate class names and cover media with transparent overlays, so media is
// found by what is under the pointer and where it is served from, not by selector or event target.
(function () {
    const SITE = /(^|\.)(instagram\.com|facebook\.com|vsco\.co)$/;
    if (!SITE.test(location.hostname)) return;

    const CDN = /(^|\.)(cdninstagram\.com|fbcdn\.net|vsco\.co)$/;
    const MIN_SIZE = 120;       // skips avatars and icons
    const INSET = 8;
    const HANDLER = 'nookSocialImageDownload';

    const DOWNLOAD_ICON = 'M8 2.5v8M4.5 7 8 10.5 11.5 7M3 13.5h10';
    const DONE_ICON = 'M3.5 8.5 6.5 11.5 12.5 4.5';
    const SVG = 'http://www.w3.org/2000/svg';

    let host, button, icon, current = null;
    // Videos with no saveable URL, by the source they were playing; a miss costs a React tree walk.
    const misses = new WeakMap();

    function cdnURL(value) {
        try {
            const url = new URL(value, location.href);
            return url.protocol === 'https:' && CDN.test(url.hostname) ? url.href : null;
        } catch { return null; }
    }

    // Largest candidate from srcset (w or x descriptors), falling back to what is showing.
    function imageURL(img) {
        let best = cdnURL(img.currentSrc || img.src), bestScore = 0;
        const sets = [img.getAttribute('srcset')];
        if (img.parentElement?.tagName === 'PICTURE') {
            for (const source of img.parentElement.querySelectorAll('source[srcset]')) sets.push(source.getAttribute('srcset'));
        }
        for (const set of sets) {
            // Instagram omits the space after each comma; split only where a URL starts.
            for (const candidate of (set || '').split(/,\s*(?=https:|\/)/)) {
                const [src, descriptor = '1x'] = candidate.trim().split(/\s+/);
                const url = cdnURL(src);
                const score = parseFloat(descriptor) * (descriptor.endsWith('x') ? img.naturalWidth || 1 : 1);
                if (url && score > bestScore) { best = url; bestScore = score; }
            }
        }
        // VSCO resizes by query (?w=1600); without one im.vsco.co serves the original upload.
        if (best && /(^|\.)vsco\.co$/.test(new URL(best).hostname)) {
            const original = new URL(best);
            original.search = '';
            return original.href;
        }
        return best;
    }

    // Facebook and Instagram stream video as blob: URLs; social-video-source.js reads the MP4 from the
    // page's React data and answers in an attribute during dispatchEvent. A direct CDN src also works.
    function videoSource(video) {
        video.dispatchEvent(new CustomEvent('nook-social-video-url'));
        const answer = video.getAttribute('data-nook-video-url');
        video.removeAttribute('data-nook-video-url');
        try {
            const { url, note } = JSON.parse(answer);
            if (cdnURL(url)) return { url, note };
        } catch {}
        const direct = cdnURL(video.currentSrc || video.src);
        return direct && { url: direct, note: 'src' };
    }

    function sourceFor(element) {
        if (element.tagName === 'VIDEO') return videoSource(element);
        const url = imageURL(element);
        return url && { url };
    }

    const isMedia = element => element.tagName === 'VIDEO' || (element.tagName === 'IMG' && cdnURL(element.currentSrc || element.src));
    const contains = (rect, x, y) => x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;

    function mediaAt(x, y) {
        const stack = document.elementsFromPoint(x, y);
        let element = stack.find(isMedia);
        // Hit testing skips pointer-events: none, which VSCO sets on every photo. Look inside the topmost
        // element instead; it is the photo's wrapper there and a small overlay on the other sites.
        // ponytail: topmost element only; widen to its parent if another site nests the image beside it.
        if (!element && stack[0]) {
            element = [...stack[0].getElementsByTagName('img')].find(img => isMedia(img) && contains(img.getBoundingClientRect(), x, y));
        }
        if (!element) return null;
        const rect = element.getBoundingClientRect();
        return rect.width >= MIN_SIZE && rect.height >= MIN_SIZE ? element : null;
    }

    // Album grids crop a larger image inside an overflow-hidden tile, so the image's own box runs past
    // the tile. Clip it to every clipping ancestor and the viewport. Runs only when the hovered image changes.
    function visibleRect(element) {
        const r = element.getBoundingClientRect();
        let top = Math.max(r.top, 0), right = Math.min(r.right, innerWidth);
        for (let el = element.parentElement; el && el !== document.body; el = el.parentElement) {
            if (getComputedStyle(el).overflow === 'visible') continue;
            const clip = el.getBoundingClientRect();
            top = Math.max(top, clip.top);
            right = Math.min(right, clip.right);
        }
        return { top, right };
    }

    function ensureButton() {
        if (host) {
            if (!host.isConnected) document.documentElement.appendChild(host);
            return;
        }
        // No innerHTML: Facebook and Instagram enforce Trusted Types.
        host = document.createElement('div');
        const root = host.attachShadow({ mode: 'closed' });
        const style = document.createElement('style');
        style.textContent = `
            button { position: fixed; z-index: 2147483647; display: none; width: 32px; height: 32px; padding: 0;
                     align-items: center; justify-content: center; border: 0; border-radius: 16px; cursor: pointer;
                     color: #fff; background: rgba(0,0,0,.55); -webkit-backdrop-filter: blur(12px); }
            button:hover { background: rgba(0,0,0,.75); }
            svg { width: 16px; height: 16px; fill: none; stroke: currentColor; stroke-width: 1.7; stroke-linecap: round; stroke-linejoin: round; }`;
        button = document.createElement('button');
        button.type = 'button';
        button.title = 'Download';
        button.setAttribute('aria-label', 'Download');
        const svg = document.createElementNS(SVG, 'svg');
        svg.setAttribute('viewBox', '0 0 16 16');
        icon = document.createElementNS(SVG, 'path');
        svg.appendChild(icon);
        button.appendChild(svg);
        root.append(style, button);
        button.addEventListener('click', event => {
            event.preventDefault();
            event.stopPropagation();
            // A carousel can slide while the pointer rests on its arrow; take the media under the click.
            const element = mediaAt(event.clientX, event.clientY) || current;
            const source = element && sourceFor(element);
            if (!source) return;
            window.webkit.messageHandlers[HANDLER].postMessage(source);
            icon.setAttribute('d', DONE_ICON);
        });
        document.documentElement.appendChild(host);
    }

    function hide() {
        current = null;
        if (button) button.style.display = 'none';
    }

    // mouseover fires only when the element under the pointer changes, so this does no work while
    // the pointer moves within one element.
    document.addEventListener('mouseover', event => {
        if (host && event.target === host) return;
        const element = mediaAt(event.clientX, event.clientY);
        if (element === current && element) return;
        if (!element || misses.get(element) === (element.currentSrc || element.src)) return hide();
        if (!sourceFor(element)) {
            if (element.tagName === 'VIDEO') misses.set(element, element.currentSrc || element.src);
            return hide();
        }
        current = element;
        ensureButton();
        const rect = visibleRect(element);
        icon.setAttribute('d', DOWNLOAD_ICON);
        button.style.top = `${rect.top + INSET}px`;
        button.style.left = `${rect.right - INSET - 32}px`;
        button.style.display = 'flex';
    }, { capture: true, passive: true });

    document.addEventListener('mouseout', event => { if (!event.relatedTarget) hide(); }, { capture: true, passive: true });
    // Only a scroll that moves the hovered image; stories and carousels scroll their own trays.
    window.addEventListener('scroll', event => {
        if (current && (event.target === document || event.target.contains?.(current))) hide();
    }, { capture: true, passive: true });
})();
