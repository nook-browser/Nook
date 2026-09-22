// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  NookSwitch.swift
//  Nook
//
//  Created by Bain Gurley on 21/09/2026.
//

import SwiftUI
import NookDesign

/// A switch that shows its on state regardless of window emphasis. AppKit draws `.switch` in a
/// non-key window unemphasized, so a system toggle inside a floating panel reads as grey and off.
/// Panels stay non-key on purpose: a key borderless panel gets a heavier window shadow that cuts
/// a hard edge around its glass.
public struct NookSwitchToggleStyle: ToggleStyle {
    private let trackWidth: CGFloat = 38
    private let trackHeight: CGFloat = 22
    private let knob: CGFloat = 18

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Capsule()
            .fill(configuration.isOn ? Color.accentColor : NookDesign.Surface.fillPressed)
            .frame(width: trackWidth, height: trackHeight)
            .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    .padding(2)
            }
            .animation(NookDesign.Motion.quick, value: configuration.isOn)
            .onTapGesture { configuration.isOn.toggle() }
            .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}
