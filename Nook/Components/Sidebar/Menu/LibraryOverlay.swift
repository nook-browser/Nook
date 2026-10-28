// Licensed under GPL-3.0. See LICENSE.
//
//  LibraryOverlay.swift
//  Nook
//
//  The library (History, Downloads, Spaces), uncovered as the whole browser slides aside, as
//  in Arc. A swipe past the first space pushes the browser under the fingers (the space pager
//  tracks it); a sideways swipe anywhere while it is open pulls the browser home
//  (`LibrarySwipeSurface`). Both end in `LibraryMotion.release`, one rule, one spring.
//

import AppKit
import OSLog
import SwiftUI
import NookDesign
import NookTabsCore
import NookWeb
import NookUI

@MainActor
enum LibraryMotion {
    private static let log = Logger(subsystem: "com.gstudios.nook", category: "Library")

    /// Critically damped for a tap; a released swipe gets a touch of bounce (`release`).
    static let open = Animation.interpolatingSpring(Spring(response: 0.32, dampingRatio: 1))
    static let dismiss = Animation.interpolatingSpring(Spring(response: 0.28, dampingRatio: 1))

    private static let listWidth: CGFloat = 420
    private static let spacesWidth: CGFloat = 840

    static func width(for tab: NookWeb.SidebarMenuTab) -> CGFloat {
        tab == .spaces ? spacesWidth : listWidth
    }

    /// Settles a swipe: open or shut by where it was heading, from where the fingers left it.
    static func release(_ windowState: BrowserWindowState, distance: CGFloat, velocity: CGFloat, width: CGFloat) {
        let wasOpen = windowState.isSidebarMenuVisible
        let opens = LibrarySwipeDecision.opens(distance: distance, velocity: velocity, width: width, wasOpen: wasOpen)
        log.debug("Library release: distance \(distance, format: .fixed(precision: 0)) velocity \(velocity, format: .fixed(precision: 0)) wasOpen \(wasOpen) opens \(opens)")
        let remaining = (opens ? width : 0) - min(max(distance, 0), width)
        let relativeVelocity = abs(remaining) > 1 ? velocity / remaining : 0
        let spring = Spring(response: 0.32, dampingRatio: opens && velocity > 0 ? 0.86 : 1)
        withAnimation(.interpolatingSpring(spring, initialVelocity: relativeVelocity)) {
            windowState.libraryDrag = nil
            windowState.isSidebarMenuVisible = opens
        }
    }

    /// Opens it from a button: any swipe state left over is dropped, so the button always wins.
    static func present(_ windowState: BrowserWindowState) {
        withAnimation(open) {
            windowState.libraryDrag = nil
            windowState.isSidebarMenuVisible = true
        }
    }

    static func close(_ windowState: BrowserWindowState) {
        withAnimation(dismiss) {
            windowState.libraryDrag = nil
            windowState.isSidebarMenuVisible = false
        }
    }
}

extension LibraryMotion {
    /// Room left for the page at the far edge, so the window never fills with library.
    static let pageMargin: CGFloat = 160

    static func width(for tab: NookWeb.SidebarMenuTab, windowWidth: CGFloat) -> CGFloat {
        min(width(for: tab), max(windowWidth - pageMargin, 0))
    }

    /// How far the library is out: where a swipe holds it, rubber-banded past fully open,
    /// otherwise open or shut. The browser beside it moves by exactly this much.
    static func shown(_ windowState: BrowserWindowState, width: CGFloat) -> CGFloat {
        guard let drag = windowState.libraryDrag else { return windowState.isSidebarMenuVisible ? width : 0 }
        guard drag > width else { return max(drag, 0) }
        let over = drag - width
        return width + over * 0.55 * width / (width + 0.55 * over)
    }
}

/// The browser and the library behind it. The only view that reads the library's position, so a
/// swipe, which moves it on every trackpad event, re-renders this and nothing above it.
struct LibraryPushContainer<Content: View>: View {
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) private var nookSettings
    /// Whether the window buttons show at rest (the sidebar, or its hover overlay, is out).
    let lightsVisible: Bool
    @ViewBuilder let content: Content

    init(lightsVisible: Bool, @ViewBuilder content: () -> Content) {
        self.lightsVisible = lightsVisible
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            let width = LibraryMotion.width(for: windowState.sidebarMenuSelectedTab, windowWidth: proxy.size.width)
            let shown = LibraryMotion.shown(windowState, width: width)
            let progress = width > 0 ? min(shown / width, 1) : 0
            let onRight = nookSettings.sidebarPosition == .right
            // The sidebar fades into the library, so the page travels only as far as it takes to
            // sit beside the library, not the library's width on top of the sidebar's.
            let sidebar = windowState.isSidebarVisible ? windowState.sidebarWidth : 0
            let push = max(shown - sidebar * progress, 0)
            ZStack {
                // As in Arc, the window buttons go with the sidebar over the first half of the pull
                // and come back with the library over the second; at rest they belong to whichever
                // is showing.
                TrafficLights(visible: lightsVisible || progress > 0, alpha: abs(1 - 2 * progress))
                    .frame(width: 0, height: 0)
                LibraryPanel(width: width, shown: shown)
                content
                    .environment(\.libraryProgress, progress)
                    .offset(x: onRight ? -push : push)
                // While the library is out, a click on the page beside it brings the page back.
                // Only beside it: an overlay on the moved browser stays at the browser's old
                // frame (offset moves drawing, not layout) and swallowed every click in the library.
                if shown > 0 {
                    HStack(spacing: 0) {
                        if !onRight { Color.clear.frame(width: shown).allowsHitTesting(false) }
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { LibraryMotion.close(windowState) }
                        if onRight { Color.clear.frame(width: shown).allowsHitTesting(false) }
                    }
                }
                // While it is open, a sideways swipe anywhere pushes it shut under the fingers.
                if windowState.isSidebarMenuVisible {
                    LibrarySwipeSurface(width: width, onRight: onRight,
                                        onChange: { windowState.libraryDrag = max($0, 0) },
                                        onEnd: { LibraryMotion.release(windowState, distance: $0, velocity: $1, width: width) })
                }
            }
        }
    }
}

extension EnvironmentValues {
    /// How far the library is out, 0...1. Only `LibraryFade` reads it, so a swipe redraws that alone.
    @Entry var libraryProgress: CGFloat = 0
}

/// The sidebar giving way to the library: fading and drifting toward it, gone once it is out.
struct LibraryFade: ViewModifier {
    @Environment(\.libraryProgress) private var progress

    func body(content: Content) -> some View {
        // Gone by half way. Opacity only: a blur or scale here flattens the AppKit views inside
        // (the space pager tracking the very swipe) into a picture, and the swipe breaks.
        let out = min(progress * 2, 1)
        content
            .opacity(1 - out)
            // Under the library from the first point of the pull, so it never takes its clicks.
            .allowsHitTesting(progress == 0)
    }
}

/// The library as Arc lays it out: on the window's own background at the sidebar's edge, with
/// the whole browser (sidebar and page) pushed aside by `LibraryMotion.shown`. Moving the
/// browser is a transform, so the page never lays out again while it slides.
struct LibraryPanel: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(TabsController.self) private var tabs
    @Environment(\.nookSettings) private var nookSettings

    let width: CGFloat
    let shown: CGFloat

    var body: some View {
        let onRight = nookSettings.sidebarPosition == .right
        if shown > 0 {
            SidebarMenu()
                .environmentObject(browserManager)
                .environment(windowState)
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .padding(.top, NookDesign.Spacing.sidebarTop)
                .spaceThemeAppearance(theme)
                // Trails the browser in, so it reads as underneath, fading in as it comes. No blur or
                // scale: those flatten the AppKit views inside into a picture (see LibraryFade).
                .offset(x: (onRight ? 1 : -1) * (width - shown) * 0.3)
                .opacity(min(1, shown / max(width * 0.5, 1)))
                .frame(maxWidth: .infinity, alignment: onRight ? .trailing : .leading)
                .transition(.identity)
        }
    }

    private var theme: SpaceTheme? {
        guard !windowState.isIncognito, let spaceID = windowState.spaceID, spaceID != tabs.agentSpaceID else { return nil }
        return tabs.space(spaceID)?.theme
    }
}

/// While the library is open: a sideways swipe anywhere in the window pushes it shut under the
/// fingers. It tracks as the space pager does, in its own event loop, so it sees every event of the
/// swipe through to the end; nothing can leave it half way. Only scroll events reach it (clicks
/// pass straight through), and only a sideways swipe is kept: the rest go to the view beneath.
/// shortcut: a sideways swipe over Spaces columns that overflow closes rather than scrolls them;
/// give the columns their own surface if many spaces become common.
struct LibrarySwipeSurface: NSViewRepresentable {
    let width: CGFloat
    let onRight: Bool
    let onChange: (CGFloat) -> Void
    let onEnd: (_ distance: CGFloat, _ velocity: CGFloat) -> Void

    func makeNSView(context: Context) -> LibrarySwipeSurfaceView { LibrarySwipeSurfaceView() }

    func updateNSView(_ view: LibrarySwipeSurfaceView, context: Context) {
        view.width = width
        view.onRight = onRight
        view.onChange = onChange
        view.onEnd = onEnd
    }
}

final class LibrarySwipeSurfaceView: NSView {
    var width: CGFloat = 0
    var onRight = false
    var onChange: (CGFloat) -> Void = { _ in }
    var onEnd: (CGFloat, CGFloat) -> Void = { _, _ in }

    /// nil until the swipe shows its axis; true once it is the library's.
    private var claimed: Bool?
    private var travel = CGSize.zero
    /// The view the swipe would have gone to, for everything this one does not keep.
    private weak var beneath: NSView?
    private var lookingBeneath = false
    /// Momentum after a swipe this view kept is its own too.
    private var keptLast = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !lookingBeneath, NSApp.currentEvent?.type == .scrollWheel else { return nil }
        return super.hitTest(point)
    }

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas else { return forward(event) }
        if event.momentumPhase != [] {
            if !keptLast { forward(event) }
            return
        }
        switch event.phase {
        case .began, .mayBegin:
            claimed = nil
            keptLast = false
            travel = .zero
            beneath = viewBeneath(event)
            forward(event)
        case .changed where claimed == nil:
            travel.width += event.scrollingDeltaX
            travel.height += event.scrollingDeltaY
            // Ten points of hysteresis, then commit to an axis, as Apple's gestures do.
            if abs(travel.width) > 10, abs(travel.width) > abs(travel.height) {
                claimed = true
                keptLast = true
                track(from: event)
            } else if abs(travel.height) > 10 {
                claimed = false
                forward(event)
            } else {
                forward(event)
            }
        default:
            if claimed != true { forward(event) }
        }
    }

    /// Toward open is fingers left-to-right with the sidebar on the left, the other way on the right.
    private func towardOpen(_ event: NSEvent) -> CGFloat {
        onRight ? -event.scrollingDeltaX : event.scrollingDeltaX
    }

    private func track(from first: NSEvent) {
        guard let window else { return }
        var distance = width + travel.width * (onRight ? -1 : 1)
        var samples: [(time: TimeInterval, distance: CGFloat)] = [(first.timestamp, distance)]
        onChange(distance)
        let mask: NSEvent.EventTypeMask = [.scrollWheel, .mouseMoved, .mouseExited, .keyDown, .keyUp, .swipe]
        tracking: while let event = window.nextEvent(matching: mask, until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            guard event.type == .scrollWheel else {
                NSApp.sendEvent(event)
                continue
            }
            if event.momentumPhase != [] { continue }
            switch event.phase {
            case .changed:
                distance += towardOpen(event)
                samples.append((event.timestamp, distance))
                samples.removeAll { event.timestamp - $0.time > 0.1 }
                onChange(distance)
            case .ended, .cancelled:
                break tracking
            default:
                continue
            }
        }
        var velocity: CGFloat = 0
        if let a = samples.first, let b = samples.last, b.time > a.time { velocity = (b.distance - a.distance) / CGFloat(b.time - a.time) }
        claimed = nil
        onEnd(distance, velocity)
    }

    private func forward(_ event: NSEvent) {
        (beneath ?? viewBeneath(event))?.scrollWheel(with: event)
    }

    private func viewBeneath(_ event: NSEvent) -> NSView? {
        guard let content = window?.contentView else { return nil }
        lookingBeneath = true
        defer { lookingBeneath = false }
        let point = content.superview?.convert(event.locationInWindow, from: nil) ?? event.locationInWindow
        let view = content.hitTest(point)
        return view === self ? nil : view
    }
}
