//
//  DoubleClickView.swift
//  Nook
//
//  Created by Aether Aurelia on 11/10/2025.
//
//  A view that detects double-clicks without delaying single clicks.
//  Uses NSClickGestureRecognizer with delaysPrimaryMouseButtonEvents = false
//  to avoid interfering with button taps and other interactive elements.
//

import SwiftUI

struct DoubleClickView: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = DoubleClickNSView()
        view.onDoubleClick = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DoubleClickNSView)?.onDoubleClick = action
    }
}

class DoubleClickNSView: NSView {
    var onDoubleClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick))
        clickGesture.numberOfClicksRequired = 2
        clickGesture.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(clickGesture)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleDoubleClick() {
        onDoubleClick?()
    }
}
