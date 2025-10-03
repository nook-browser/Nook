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

            return candidateColors();
        })();
    """
}
