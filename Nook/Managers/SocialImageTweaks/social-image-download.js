// Runs at document start in the main frame, in its own content world.
// Shows a download button over the image under the pointer on Instagram, Facebook, and VSCO.
// Both sites obfuscate class names and cover photos with transparent overlays, so an image is
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

    function cdnURL(value) {
        try {
            const url = new URL(value, location.href);
            return url.protocol === 'https:' && CDN.test(url.hostname) ? url.href : null;
        } catch { return null; }
    }

    // Largest candidate from srcset (w or x descriptors), falling back to what is showing.
    function bestURL(img) {
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
        return best;
    }

    function imageAt(x, y) {
        for (const element of document.elementsFromPoint(x, y)) {
            if (element.tagName === 'VIDEO') return null;   // video poster frames: videos come later
            if (element.tagName !== 'IMG' || !cdnURL(element.currentSrc || element.src)) continue;
            const rect = element.getBoundingClientRect();
            return rect.width >= MIN_SIZE && rect.height >= MIN_SIZE ? element : null;
        }
        return null;
    }

    // Album grids crop a larger image inside an overflow-hidden tile, so the image's own box runs past
    // the tile. Clip it to every clipping ancestor and the viewport. Runs only when the hovered image changes.
    function visibleRect(img) {
        const r = img.getBoundingClientRect();
        let top = Math.max(r.top, 0), right = Math.min(r.right, innerWidth);
        for (let el = img.parentElement; el && el !== document.body; el = el.parentElement) {
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
        button.title = 'Download image';
        button.setAttribute('aria-label', 'Download image');
        const svg = document.createElementNS(SVG, 'svg');
        svg.setAttribute('viewBox', '0 0 16 16');
        icon = document.createElementNS(SVG, 'path');
        svg.appendChild(icon);
        button.appendChild(svg);
        root.append(style, button);
        button.addEventListener('click', event => {
            event.preventDefault();
            event.stopPropagation();
            // A carousel can slide while the pointer rests on its arrow; take the image under the click.
            const img = imageAt(event.clientX, event.clientY) || current;
            const url = img && bestURL(img);
            if (!url) return;
            window.webkit.messageHandlers[HANDLER].postMessage({ url });
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
        const img = imageAt(event.clientX, event.clientY);
        if (!img) return hide();
        if (img === current) return;
        current = img;
        ensureButton();
        const rect = visibleRect(img);
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
