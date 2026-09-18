// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  BottomBar.swift
//  NookiOS
//
//  The phone's only chrome. At rest: a dots row above back, the field and the
//  tabs button. On focus the dots and the buttons leave and the field takes the
//  width beside Cancel, so the bar is one row sitting on the keyboard. Forward
//  is edge-swipe only, as in Safari.
//
//  Reading collapses it: scrolling down shrinks the whole bar to a pill on the
//  trailing edge, under the thumb, and scrolling back up or tapping the pill
//  restores it.
//

import SwiftUI
import NookDesign
import NookUI
import NookWeb

/// Where the bar is drawn. The phone floats it over the page; the iPad puts it
/// at the foot of the sidebar, where glass over a sidebar material would be
/// glass on glass and the tabs button would duplicate the visible outline.
enum BottomBarStyle {
    case floating
    case sidebar
}

struct BottomBar: View {
    var style: BottomBarStyle = .floating
    /// Driven by the page's scroll direction. The sidebar never condenses.
    @Binding var condensed: Bool

    @EnvironmentObject private var model: BrowserModel
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var window

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var session: PageSession? { tabs.selectedSession(in: window) }

    private var isCondensed: Bool { condensed && !isFocused && style == .floating }

    var body: some View {
        HStack(spacing: 0) {
            if isCondensed { Spacer(minLength: 0) }
            barBody
                .modifier(BarBackground(style: style, condensed: isCondensed))
        }
        .animation(NookDesign.Motion.standard, value: isCondensed)
        .animation(NookDesign.Motion.standard, value: isFocused)
        .gesture(
            // The swipe covers the whole bar, field included: it is the biggest
            // target and switching tabs is the point. minimumDistance keeps taps
            // going to the field.
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard !isFocused,
                          abs(value.translation.width) > abs(value.translation.height) else { return }
                    if value.translation.width < 0 {
                        tabs.selectNext(in: window)
                    } else {
                        tabs.selectPrevious(in: window)
                    }
                    Haptics.alignment()
                }
        )
    }

    /// The host alone, on the thumb side. Tapping it brings the bar back.
    private var pill: some View {
        Button {
            condensed = false
        } label: {
            HStack(spacing: NookDesign.Spacing.sm) {
                if let itemID = tabs.selectedItemID(in: window), let item = tabs.item(itemID) {
                    ItemFavicon(item: item, session: session)
                }
                Text(session?.url.host() ?? "")
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, NookDesign.Spacing.lg)
            .frame(height: NookDesign.Size.row)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var barBody: some View {
        if isCondensed {
            pill
        } else {
            fullBar
        }
    }

    private var fullBar: some View {
        VStack(spacing: NookDesign.Spacing.md) {
            if !isFocused, style == .floating {
                SpacesList()
                    .frame(height: NookDesign.Spacing.xl)
            }

            HStack(spacing: NookDesign.Spacing.md) {
                if !isFocused {
                    Button {
                        session?.goBack()
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: NookDesign.Size.iconButton)
                    }
                    .buttonStyle(.plain)
                    .disabled(session?.canGoBack != true)
                    .foregroundStyle(session?.canGoBack == true ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                }

                AddressField(session: session, text: $text, isFocused: $isFocused) {
                    model.navigate(text)
                    isFocused = false
                }

                if isFocused {
                    Button("Cancel") { isFocused = false }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                } else if style == .floating {
                    Button {
                        model.present(.tabs)
                    } label: {
                        Image(systemName: "square.on.square")
                            .frame(width: NookDesign.Size.iconButton)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
            .frame(height: NookDesign.Size.bottomBar)
        }
        .padding(.horizontal, NookDesign.Spacing.rowPadding)
        .padding(.vertical, NookDesign.Spacing.md)
    }
}


/// Glass when the bar floats over a page; nothing when it sits in the sidebar,
/// which already has a material behind it.
private struct BarBackground: ViewModifier {
    let style: BottomBarStyle
    let condensed: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .floating where condensed:
            content.nookGlassEffect(in: Capsule())
        case .floating:
            content.nookGlassEffect(in: NookDesign.Radius.shape(NookDesign.Radius.xxl))
        case .sidebar:
            content
        }
    }
}
