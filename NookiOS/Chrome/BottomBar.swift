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

    @EnvironmentObject private var model: BrowserModel
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var window

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var session: PageSession? { tabs.selectedSession(in: window) }

    var body: some View {
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
        .modifier(BarBackground(style: style))
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
}


/// Glass when the bar floats over a page; nothing when it sits in the sidebar,
/// which already has a material behind it.
private struct BarBackground: ViewModifier {
    let style: BottomBarStyle

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .floating:
            content.nookGlassEffect(in: NookDesign.Radius.shape(NookDesign.Radius.xxl))
        case .sidebar:
            content
        }
    }
}
