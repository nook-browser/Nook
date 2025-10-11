//
//  BlurModifier.swift
//  Nook
//
//  Created by Aether on 25/03/2025.
//

import SwiftUI

private struct BlurModifier: ViewModifier {
    let isIdentity: Bool
    var intensity: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: isIdentity ? intensity : 0)
            .opacity(isIdentity ? 0 : 1)
    }
}

extension AnyTransition {
    static var blur: AnyTransition {
        .blur()
    }

    static var blurWithoutScale: AnyTransition {
        .modifier(
            active: BlurModifier(isIdentity: true, intensity: 20),
            identity: BlurModifier(isIdentity: false, intensity: 20)
        )
    }

    static func blur(
        intensity: CGFloat = 2,
        scale: CGFloat = 0.8
    ) -> AnyTransition {
        .scale(scale: scale)
            .combined(
                with: .modifier(
                    active: BlurModifier(isIdentity: true, intensity: intensity),
                    identity: BlurModifier(isIdentity: false, intensity: intensity)
                )
            )
    }
}
