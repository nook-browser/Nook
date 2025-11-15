//
//  WebViewThemeColorExtension.swift
//  Nook
//
//  Created by Jonathan Caudill on 24/09/2025.
//

import Foundation
import WebKit

// Shared theme color extraction script for webviews
extension WKWebView {
    static let themeColorExtractionScript = """
        (function() {
            function normalizeColor(value) {
                if (!value) { return null; }
                const input = String(value).trim();
                if (!input) { return null; }

                const canvas = document.createElement('canvas');
                canvas.width = 1;
                canvas.height = 1;
                const ctx = canvas.getContext('2d');
                if (!ctx) { return null; }

                ctx.fillStyle = '#000000';
                try {
                    ctx.fillStyle = input;
                } catch (e) {
                    return null;
                }

                const normalized = ctx.fillStyle;
                if (typeof normalized !== 'string') { return null; }

                if (normalized.startsWith('#')) {
                    if (normalized.length === 4) {
                        const r = normalized.charAt(1);
                        const g = normalized.charAt(2);
                        const b = normalized.charAt(3);
                        return `#${r}${r}${g}${g}${b}${b}`;
                    }
                    if (normalized.length === 7) {
                        return normalized;
                    }
                    if (normalized.length === 9) {
                        return normalized.substring(0, 7);
                    }
                }

                if (normalized.startsWith('rgb')) {
                    const match = normalized.match(/rgba?\\(([^)]+)\\)/i);
                    if (!match) { return null; }
                    const parts = match[1].split(',').map(part => part.trim());
                    if (parts.length < 3) { return null; }

                    const r = Math.round(Number(parts[0]));
                    const g = Math.round(Number(parts[1]));
                    const b = Math.round(Number(parts[2]));
                    const a = parts.length > 3 ? Number(parts[3]) : 1;

                    if ([r, g, b, a].some(Number.isNaN)) { return null; }
                    if (a === 0) { return null; }

                    const toHex = (n) => n.toString(16).padStart(2, '0');
                    return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
                }

                return null;
            }

            function candidateColors() {
                const metaNames = [
                    'theme-color',
                    'msapplication-navbutton-color',
                    'apple-mobile-web-app-status-bar-style'
                ];

                for (const name of metaNames) {
                    const element = document.querySelector(`meta[name="${name}"]`);
                    if (element) {
                        const normalized = normalizeColor(element.getAttribute('content'));
                        if (normalized) { return normalized; }
                    }
                }

                const topElement = document.elementFromPoint(window.innerWidth / 2, 1);
                if (topElement) {
                    const normalized = normalizeColor(getComputedStyle(topElement).backgroundColor);
                    if (normalized) { return normalized; }
                }

                if (document.body) {
                    const normalized = normalizeColor(getComputedStyle(document.body).backgroundColor);
                    if (normalized && normalized !== '#000000') { return normalized; }
                }

                if (document.documentElement) {
                    const normalized = normalizeColor(getComputedStyle(document.documentElement).backgroundColor);
                    if (normalized) { return normalized; }
                }

                return null;
            }

            function runExtraction() {
                try {
                    return candidateColors();
                } catch (_) {
                    return null;
                }
            }

            function waitForDarkReader(timeoutMs = 1500) {
                return new Promise((resolve) => {
                    const start = Date.now();

                    function done() { resolve(); }

                    if (typeof window.DarkReader === 'undefined' || !window.DarkReader) {
                        return done();
                    }

                    try {
                        if (typeof window.DarkReader.ready === 'function') {
                            const r = window.DarkReader.ready();
                            if (r && typeof r.then === 'function') {
                                r.then(done).catch(done);
                                return;
                            }
                        }
                    } catch (_) 
    
                    const isDarkReaderStyle = (node) => (
                        node && node.nodeType === Node.ELEMENT_NODE &&
                        node.tagName === 'STYLE' &&
                        (node.classList.contains('darkreader') || /darkreader/i.test(node.getAttribute('media') || '') || /darkreader/i.test(node.getAttribute('id') || ''))
                    );

                    let settleTimer = null;
                    const settleDelay = 100;

                    const observer = new MutationObserver(() => {
                        if (settleTimer) { clearTimeout(settleTimer); }
                        settleTimer = setTimeout(() => {
                            observer.disconnect();
                            done();
                        }, settleDelay);
                    });

                    let sawDarkReader = false;
                    try {
                        const styles = document.querySelectorAll('style, link[rel="stylesheet"]');
                        styles.forEach((el) => { if (isDarkReaderStyle(el)) { sawDarkReader = true; } });
                    } catch (_) { /* ignore */ }

                    observer.observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: ['media', 'class', 'id'] });

                    if (sawDarkReader) {
                        settleTimer = setTimeout(() => {
                            observer.disconnect();
                            done();
                        }, settleDelay);
                    }

                    const t = setInterval(() => {
                        if (Date.now() - start >= timeoutMs) {
                            try { observer.disconnect(); } catch (_) {}
                            clearInterval(t);
                            done();
                        }
                    }, 50);
                });
            }

            function waitForLoad() {
                return new Promise((resolve) => {
                    if (document.readyState === 'complete') { resolve(); return; }
                    window.addEventListener('load', () => resolve(), { once: true });
                });
            }

            return (async function() {
                try {
                    await waitForLoad();
                    await waitForDarkReader(1500);
                    return runExtraction();
                } catch (_) {
                    return null;
                }
            })();
        })();
    """
}
