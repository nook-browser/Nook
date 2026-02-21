//
//  OnboardingUtils.swift
//  Nook
//
//  Created by Maciek Bagiński on 19/02/2026.
//

import SwiftUI
import AppKit

struct BlurSlideModifier: ViewModifier {
    let offset: CGFloat
    let blur: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

extension AnyTransition {
    static var slideAndBlur: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurSlideModifier(offset: 100, blur: 10, opacity: 0.5),
                identity: BlurSlideModifier(offset: 0, blur: 0, opacity: 1)
            ),
            removal: .modifier(
                active: BlurSlideModifier(offset: -100, blur: 0, opacity: 0),
                identity: BlurSlideModifier(offset: 0, blur: 0, opacity: 1)
            )
        )
    }
}
