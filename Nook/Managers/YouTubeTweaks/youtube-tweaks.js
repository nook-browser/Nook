// Runs at document start on www.youtube.com in its own content world.
// YouTubeTweaks.swift appends the call with { css, frameThumbnails, noHoverPreview }.
(function (config) {
    if (location.hostname !== 'www.youtube.com' && location.hostname !== 'youtube.com') return;

    if (config.css) {
        const style = document.createElement('style');
        style.textContent = config.css;
        document.documentElement.appendChild(style);
    }
    if (config.noHoverPreview) {
        // YouTube starts the inline preview from JS hover events on a video card. Stop them in the
        // capture phase, before the page sees them; CSS :hover styling is unaffected.
        const CARDS = 'yt-lockup-view-model, ytd-rich-item-renderer, ytd-video-renderer, ytd-compact-video-renderer, ytd-thumbnail, ytm-shorts-lockup-view-model, ytm-shorts-lockup-view-model-v2';
        const stop = event => { if (event.target.closest?.(CARDS)) event.stopImmediatePropagation(); };
        for (const type of ['mouseover', 'mouseenter', 'mousemove', 'pointerover', 'pointerenter', 'pointermove']) {
            window.addEventListener(type, stop, true);
        }
    }
    if (!config.frameThumbnails) return;

    // MARK: - Frame thumbnails
    // YouTube publishes three frames per video (hq1, hq2, hq3, roughly 25/50/75% in).
    // Swap the uploader's thumbnail for one of them.

    const THUMBNAIL = /^https:\/\/i\.ytimg\.com\/vi(?:_webp)?\/([\w-]{11})\/(?:hq720|hqdefault|mqdefault|sddefault|maxresdefault)\.(?:jpg|webp)/;

    function swap(img) {
        const match = THUMBNAIL.exec(img.getAttribute('src') || '');
        if (!match) return;
        const id = match[1];
        if (img.dataset.nookFrameFailed === id) return;

        const original = img.getAttribute('src');
        // Same frame for a video every time it appears.
        const frameURL = `https://i.ytimg.com/vi/${id}/hq${1 + (id.charCodeAt(0) + id.charCodeAt(10)) % 3}.jpg`;
        // Missing frames come back as an error or a 120px placeholder; YouTube may have recycled the img by then.
        const revert = () => {
            if (img.getAttribute('src') !== frameURL) return;
            img.dataset.nookFrameFailed = id;
            img.removeAttribute('data-nook-frame');
            img.setAttribute('src', original);
        };
        img.addEventListener('error', revert, { once: true });
        img.addEventListener('load', () => { if (img.naturalWidth <= 120) revert(); }, { once: true });
        img.dataset.nookFrame = '';
        img.setAttribute('src', frameURL);
    }

    new MutationObserver(records => {
        for (const record of records) {
            if (record.type === 'attributes') {
                if (record.target.tagName === 'IMG') swap(record.target);
                continue;
            }
            for (const node of record.addedNodes) {
                if (node.nodeType !== Node.ELEMENT_NODE) continue;
                if (node.tagName === 'IMG') swap(node);
                else node.querySelectorAll('img[src^="https://i.ytimg.com/vi"]').forEach(swap);
            }
        }
    }).observe(document.documentElement, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] });
})
