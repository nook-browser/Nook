// Licensed under GPL-3.0. See LICENSE.
// Native interpretation of Zen's layered color washes and textured browser chrome.
// No Zen source or image assets are embedded here.
import SwiftUI
import NookDesign
import NookTabsCore
#if os(macOS)
import AppKit
#endif

/// Shared window-coordinate background for the sidebar and the frame surrounding web pages.
public struct SpaceThemeSurface: View {
    public var appearance: SpaceAppearance
    public var isActive: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(appearance: SpaceAppearance, isActive: Bool = true) {
        self.appearance = appearance
        self.isActive = isActive
    }

    private var dark: Bool {
        appearance.mode == .dark || (appearance.mode == .system && colorScheme == .dark)
    }

    public var body: some View {
        let theme = appearance.normalized
        let colors = theme.nodes.map { wash($0.colorHex) }
        ZStack {
            if reduceTransparency {
                NookDesign.Surface.windowBackground
            } else {
                #if os(macOS)
                ChromeMaterial()
                #else
                Rectangle().fill(.regularMaterial)
                #endif
            }
            ZStack {
                if colors.count == 1 {
                    colors[0]
                } else if colors.count == 2 {
                    LinearGradient(colors: [colors[0], colors[1]], startPoint: UnitPoint(x: 0.25, y: 0), endPoint: UnitPoint(x: 0.75, y: 1))
                } else {
                    colors[2]
                    GeometryReader { proxy in
                        let radius = max(proxy.size.width, proxy.size.height) * 0.95
                        RadialGradient(colors: [colors[1], colors[1].opacity(0)], center: .topTrailing, startRadius: 0, endRadius: radius)
                        RadialGradient(colors: [colors[0], colors[0].opacity(0)], center: .topLeading, startRadius: 0, endRadius: radius * 0.85)
                    }
                }
            }
            .opacity(theme.opacity * (isActive ? 1 : 0.65))
            if theme.grain > 0, let texture = ChromeGrain.image {
                Image(decorative: texture, scale: 1)
                    .resizable(resizingMode: .tile)
                    .blendMode(.softLight)
                    .opacity(theme.grain * 0.35)
            }
        }
        .clipped()
        .contentShape(Rectangle())
        .accessibilityHidden(true)
    }

    private func wash(_ hex: String) -> Color {
        // Explicit colors avoid resolving a dynamic NSColor in the wrong window appearance.
        let cleaned = String(hex.suffix(6))
        let value = UInt32(cleaned, radix: 16) ?? 0x7C7C7C
        let components = [Double((value >> 16) & 255), Double((value >> 8) & 255), Double(value & 255)].map { $0 / 255 }
        let mix = dark ? 0.48 : 0.18
        let base = dark ? 0.035 : 1.0
        let c = components.map { $0 * (1 - mix) + base * mix }
        return Color(red: c[0], green: c[1], blue: c[2])
    }
}

#if os(macOS)
private struct ChromeMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
#endif

private enum ChromeGrain {
    // Generated once, tiled at native scale. No animation, timers or per-frame random work.
    static let image: CGImage? = {
        let side = 128
        var state: UInt32 = 0x4E4F4F4B
        let bytes: [UInt8] = (0..<(side * side)).map { _ in
            state = state &* 1664525 &+ 1013904223
            return UInt8(state >> 24)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8,
                       bytesPerRow: side, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }()
}
