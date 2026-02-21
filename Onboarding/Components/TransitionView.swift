//
//  TransitionView.swift
//  Nook
//
//  Created by Maciek Bagiński on 17/02/2026.
//

import AppKit
import SwiftUI

private struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        DispatchQueue.main.async { self.onChange(window) }
    }
}

struct TransitionView<A: View, B: View>: View {
    let viewA: A
    let viewB: B
    @Binding var showB: Bool

    @State private var progress: Float = 0
    @State private var snapshot: CGImage?
    @State private var renderedShowB: Bool
    @State private var nsWindow: NSWindow?

    init(
        showB: Binding<Bool>,
        @ViewBuilder viewA: () -> A,
        @ViewBuilder viewB: () -> B
    ) {
        self._showB = showB
        self.viewA = viewA()
        self.viewB = viewB()
        self._renderedShowB = State(initialValue: showB.wrappedValue)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                viewA
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(renderedShowB ? 0 : 1)
                    .allowsHitTesting(!renderedShowB)

                viewB
                    .frame(width: geo.size.width, height: geo.size.height)
                    .opacity(renderedShowB ? 1 : 0)
                    .allowsHitTesting(renderedShowB)
                    .alwaysArrowCursor()

                if let cg = snapshot {
                    Image(cg, scale: 1, label: Text(""))
                        .resizable()
                        .scaledToFill()
                        .allowsHitTesting(false)
                        .colorEffect(
                            ShaderLibrary.transitionReveal(
                                .float(progress),
                                .float2(
                                    Float(geo.size.width),
                                    Float(geo.size.height)
                                )
                            )
                        )
                }
            }
        }
        .ignoresSafeArea(.all)
        .background(WindowReader { nsWindow = $0 })
        .onChange(of: showB) { _, new in
            guard new != renderedShowB else { return }
            DispatchQueue.main.async { beginTransition(to: new) }
        }
    }

    private func captureSnapshot() -> CGImage? {
        guard let contentView = nsWindow?.contentView else { return nil }
        let bounds = contentView.bounds
        guard let rep = contentView.bitmapImageRepForCachingDisplay(in: bounds)
        else { return nil }
        contentView.cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    private func beginTransition(to newValue: Bool) {
        snapshot = captureSnapshot()
        progress = 0
        renderedShowB = newValue

        withAnimation(.easeInOut(duration: 0.55)) {
            progress = 1.0
        } completion: {
            snapshot = nil
            progress = 0
        }
    }
}
