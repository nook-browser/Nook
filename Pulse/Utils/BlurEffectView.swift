//
//  BlurEffectView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 28/07/2025.
//
import AppKit
import SwiftUI

struct BlurEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var state: NSVisualEffectView.State

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.state = .active
        view.blendingMode = .behindWindow
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.state = state
    }
}
