// Licensed under GPL-3.0. See LICENSE.
//
//  RoundedSpinner.swift
//  Nook
//
//  Created by Maciek Bagiński on 19/02/2026.
//

import AppKit
import SwiftUI

/// Turns in Core Animation, so it keeps spinning while the main thread is busy.
struct RoundedSpinner: NSViewRepresentable {
    var color: Color = .primary

    func makeNSView(context: Context) -> SpinnerView {
        SpinnerView()
    }

    func updateNSView(_ view: SpinnerView, context: Context) {
        view.arc.strokeColor = color.resolve(in: context.environment).cgColor
    }

    final class SpinnerView: NSView {
        let arc = CAShapeLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            arc.fillColor = nil
            arc.lineWidth = 2.5
            arc.lineCap = .round
            arc.strokeStart = 0.05
            arc.strokeEnd = 0.75
            layer?.addSublayer(arc)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            arc.frame = bounds
            arc.path = CGPath(ellipseIn: bounds.insetBy(dx: arc.lineWidth / 2, dy: arc.lineWidth / 2), transform: nil)
            CATransaction.commit()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, arc.animation(forKey: "spin") == nil else { return }
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.byValue = -2 * Double.pi
            spin.duration = 0.8
            spin.repeatCount = .infinity
            arc.add(spin, forKey: "spin")
        }
    }
}

/// Where a `RoundedSpinner` stood when the work finished: draws a circle, then a tick inside it.
struct RoundedCheckmark: View {
    @State private var circle: CGFloat = 0
    @State private var tick: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: circle)
                .stroke(.foreground, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Tick()
                .trim(from: 0, to: tick)
                .stroke(.foreground, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { circle = 1 }
            withAnimation(.easeOut(duration: 0.2).delay(0.25)) { tick = 1 }
        }
    }

    private struct Tick: Shape {
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.52))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.45, y: rect.minY + rect.height * 0.67))
                path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.36))
            }
        }
    }
}
