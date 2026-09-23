// Licensed under GPL-3.0. See LICENSE.
//
//  DownloadFlightOverlay.swift
//  Nook
//
//  A starting download flies from where it was clicked to the sidebar's downloads button, so it
//  is plain where the file went.
//

import AppKit
import SwiftUI
import NookDesign
import NookWeb

/// Where the downloads button sits, reported so a starting download can fly to it.
struct DownloadsButtonAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

struct DownloadFlightOverlay: View {
    /// Nil while the button is off screen (sidebar hidden, history panel open): nothing flies then.
    let target: Anchor<CGRect>?

    @Environment(BrowserWindowState.self) private var windowState
    @State private var flights: [Flight] = []

    private struct Flight: Identifiable {
        let id = UUID()
        let icon: NSImage
        let start: CGPoint
        let end: CGPoint
    }

    private let iconSize: CGFloat = 32

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(flights) { flight in
                    FlyingIcon(icon: flight.icon, start: flight.start, end: flight.end, size: iconSize) {
                        flights.removeAll { $0.id == flight.id }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onReceive(NotificationCenter.default.publisher(for: .downloadDidStart)) { note in
                guard let download = note.object as? Download,
                      let window = windowState.window,
                      download.sourceWindow === window,
                      let launch = download.launchPoint,
                      let contentView = window.contentView,
                      let target else { return }
                // AppKit window point to this overlay's space: flip to a top-left origin, then
                // offset by where the overlay sits in the window.
                let inContent = contentView.convert(launch, from: nil)
                let top = contentView.isFlipped ? inContent.y : contentView.bounds.height - inContent.y
                let origin = proxy.frame(in: .global).origin
                let start = CGPoint(x: inContent.x - origin.x, y: top - origin.y)
                let button = proxy[target]
                flights.append(Flight(icon: download.icon, start: start, end: CGPoint(x: button.midX, y: button.midY)))
            }
        }
        .allowsHitTesting(false)
    }
}

/// One icon on its way: up and over in an arc, shrinking into the button.
private struct FlyingIcon: View {
    let icon: NSImage
    let start: CGPoint
    let end: CGPoint
    let size: CGFloat
    let onArrival: () -> Void

    @State private var progress: CGFloat = 0

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .modifier(ArcFlight(progress: progress, start: start, end: end))
            .onAppear {
                withAnimation(NookDesign.Motion.flight) {
                    progress = 1
                } completion: {
                    onArrival()
                }
            }
    }
}

/// Position along a quadratic curve whose control point sits above both ends, so the icon
/// rises before it drops into the button, as Safari's does.
private struct ArcFlight: ViewModifier, Animatable {
    var progress: CGFloat
    let start: CGPoint
    let end: CGPoint

    private let rise: CGFloat = 120
    private let arrivalScale: CGFloat = 0.4

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - rise)
        let t = progress, u = 1 - progress
        let x = u * u * start.x + 2 * u * t * control.x + t * t * end.x
        let y = u * u * start.y + 2 * u * t * control.y + t * t * end.y
        content
            .scaleEffect(1 - (1 - arrivalScale) * t)
            .opacity(t < 0.8 ? 1 : (1 - t) / 0.2)
            .position(x: x, y: y)
    }
}
