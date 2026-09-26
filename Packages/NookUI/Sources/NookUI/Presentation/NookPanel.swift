// Licensed under GPL-3.0. See LICENSE.

import SwiftUI
import NookDesign

/// Shared glass surface for dialogs and larger in-window panels.
public struct NookPanel<Content: View>: View {
    private let maxWidth: CGFloat?
    private let padding: CGFloat
    private let content: Content

    public init(
        maxWidth: CGFloat? = nil,
        padding: CGFloat = NookDesign.Spacing.xl,
        @ViewBuilder content: () -> Content
    ) {
        self.maxWidth = maxWidth
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .nookGlassEffect(in: NookDesign.Radius.shape(NookDesign.Radius.xl))
            // Empty panel chrome still needs to absorb taps above the modal scrim.
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.xl))
            .onTapGesture { }
    }
}

/// Centers arbitrary panel content over the current window.
public struct NookModalOverlay<Content: View>: View {
    @State private var hasAppeared = false
    private let isPresented: Bool
    private let onDismiss: () -> Void
    private let content: Content

    public init(
        isPresented: Bool,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.isPresented = isPresented
        self.onDismiss = onDismiss
        self.content = content()
    }

    public var body: some View {
        ZStack {
            if isPresented && hasAppeared {
                NookDesign.Surface.scrim
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
                    .transition(.opacity)

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.asymmetric(
                        insertion: .offset(y: 30).combined(with: .blur(intensity: 3, scale: 1)),
                        removal: .offset(y: -30).combined(with: .blur(intensity: 3, scale: 1))
                    ))
                    .zIndex(1)
            }
        }
        .animation(NookDesign.Motion.spring, value: isPresented)
        .onAppear {
            withAnimation(NookDesign.Motion.spring) {
                hasAppeared = true
            }
        }
    }
}
