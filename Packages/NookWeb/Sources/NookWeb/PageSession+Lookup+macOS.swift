// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+Lookup+macOS.swift
//  NookWeb
//
//  What Look It Up reads off a booking page beyond its text: its controls by label, its
//  heading, and a picture of its top. Also the one click it may make, on a control it listed.
//

#if os(macOS)
import AppKit
import WebKit

extension PageSession {
    private static let maxControls = 80
    private static let shotSize = NSSize(width: 1100, height: 820)

    // What a person could press, in page order, each numbered in the DOM so a later click finds
    // it again. Header, footer and nav are left out; an open dialog is the whole list.
    private static let controlsScript = """
        (() => {
          document.querySelectorAll('[data-nk]').forEach(e => e.removeAttribute('data-nk'));
          const seen = new Set(), out = [];
          const scope = document.querySelector('[role=dialog],[aria-modal=true]') || document;
          for (const el of scope.querySelectorAll('a[href],button,input,select,textarea,[role=button],[role=option],[role=tab],[role=menuitem],[role=gridcell],[role=combobox]')) {
            const r = el.getBoundingClientRect(), st = getComputedStyle(el);
            if (r.width < 4 || r.height < 4 || st.visibility === 'hidden' || st.display === 'none' || el.disabled || el.getAttribute('aria-disabled') === 'true') continue;
            if (el.closest('header,footer,nav')) continue;
            const label = (el.getAttribute('aria-label') || el.innerText || el.value || el.placeholder || el.title || '').replace(/\\s+/g, ' ').trim().slice(0, 60);
            if (!label) continue;
            const pressed = el.tagName === 'BUTTON' || el.getAttribute('role') === 'button' || (el.tagName === 'INPUT' && ['button','submit'].includes(el.type));
            const kind = el.tagName === 'A' ? 'link' : (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') && !['button','submit','checkbox','radio'].includes(el.type) ? 'field' : el.tagName === 'SELECT' ? 'menu' : pressed ? 'button' : 'choice';
            const key = kind + ' ' + label;
            if (seen.has(key)) continue;
            seen.add(key);
            el.setAttribute('data-nk', String(out.length));
            out.push(key);
            if (out.length >= \(maxControls)) break;
          }
          return out.join('\\n');
        })()
        """

    /// The page's controls as "kind label" ("button 7:00 PM Dining Room"), in page order. An
    /// index into the result names the same control to `clickControl(at:)`.
    public func readControlLabels(within seconds: Double = 3) async -> [String] {
        let listed = await answer(to: Self.controlsScript, within: seconds) as? String ?? ""
        return listed.split(separator: "\n").map(String.init)
    }

    /// The page's first heading, which on a venue's page is the venue.
    public func readHeading(within seconds: Double = 3) async -> String {
        let script = "((document.querySelector('h1') || {}).innerText || '').replace(/\\s+/g, ' ').trim().slice(0, 80)"
        return await answer(to: script, within: seconds) as? String ?? ""
    }

    /// Presses the control `readControlLabels()` listed at `index`. False when it is gone.
    public func clickControl(at index: Int, within seconds: Double = 3) async -> Bool {
        let script = """
            (() => {
              const el = document.querySelector('[data-nk="\(index)"]');
              if (!el) return false;
              el.scrollIntoView({block: 'center'});
              for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup']) {
                el.dispatchEvent(new MouseEvent(type, {bubbles: true, cancelable: true, view: window}));
              }
              el.click();
              return true;
            })()
            """
        return await answer(to: script, within: seconds) as? Bool ?? false
    }

    /// A JPEG of the top of the page, `width` points wide. Nil when the page will not draw in time.
    public func snapshotJPEG(width: CGFloat, within seconds: Double = 3) async -> Data? {
        guard let webView else { return nil }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = NSRect(origin: .zero, size: Self.shotSize)
        configuration.snapshotWidth = NSNumber(value: Double(width))
        let image: NSImage? = await withCheckedContinuation { continuation in
            var answered = false
            func answer(_ image: NSImage?) {
                guard !answered else { return }
                answered = true
                continuation.resume(returning: image)
            }
            webView.takeSnapshot(with: configuration) { image, _ in answer(image) }
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { answer(nil) }
        }
        guard let tiff = image?.tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)?.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
}
#endif
