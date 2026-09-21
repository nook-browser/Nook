// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  SpaceSeparator.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI
import NookDesign

public struct SpaceSeparator: View {
    @Binding var isHovering: Bool
    let onClear: () -> Void
    let onOrganize: (() -> Void)?
    let isOrganizing: Bool
    let tabCount: Int
    @State private var isClearHovered: Bool = false
    @State private var isOrganizeHovered: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isHovering: Binding<Bool>,
        onClear: @escaping () -> Void,
        onOrganize: (() -> Void)?,
        isOrganizing: Bool,
        tabCount: Int
    ) {
        self._isHovering = isHovering
        self.onClear = onClear
        self.onOrganize = onOrganize
        self.isOrganizing = isOrganizing
        self.tabCount = tabCount
    }

    public var body: some View {
        let hasTabs = tabCount > 0
        HStack(spacing: 0) {
            // The rule itself is the progress indicator: it ripples while the organizer works.
            TimelineView(.animation(paused: !isWaving)) { timeline in
                WaveLine(
                    amplitude: isWaving ? NookDesign.Size.waveAmplitude : 0,
                    phase: timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: NookDesign.Motion.wavePeriod)
                        / NookDesign.Motion.wavePeriod * 2 * .pi
                )
                .stroke(
                    isWaving ? Color.accentColor : NookDesign.Surface.hairline,
                    style: StrokeStyle(lineWidth: NookDesign.Size.hairlineWidth, lineCap: .round)
                )
            }
            .padding(.horizontal, NookDesign.Spacing.md)
            .animation(NookDesign.Motion.settle, value: isWaving)
            .animation(NookDesign.Motion.quick, value: isHovering)

            // Organize button (trailing side)
            if hasTabs && tabCount >= 5 && isHovering {
                if isOrganizing {
                    // Reduce Motion keeps the spinner in place of the wave.
                    if reduceMotion {
                        ProgressView()
                            .controlSize(.mini)
                            .padding(.horizontal, NookDesign.Spacing.xs)
                            .transition(.blur.animation(NookDesign.Motion.quick))
                    }
                } else if let onOrganize {
                    Button(action: onOrganize) {
                        HStack(spacing: NookDesign.Spacing.xs) {
                            Image(systemName: "wand.and.stars")
                                .font(NookDesign.Font.caption)
                            Text("Organize")
                                .font(NookDesign.Font.caption)
                        }
                        .foregroundStyle(isOrganizeHovered ? .primary : .tertiary)
                        .padding(.horizontal, NookDesign.Spacing.xs)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Organize tabs with AI")
                    .transition(.blur.animation(NookDesign.Motion.quick))
                    .onHoverTracking { state in
                        isOrganizeHovered = state
                    }
                }
            }

            // Clear button (trailing side)
            if hasTabs && isHovering {
                Button(action: onClear) {
                    HStack(spacing: NookDesign.Spacing.xs) {
                        Image(systemName: "arrow.down")
                            .font(NookDesign.Font.caption)
                        Text("Clear")
                            .font(NookDesign.Font.caption)
                    }
                    .foregroundStyle(isClearHovered ? .primary : .tertiary)
                    .padding(.horizontal, NookDesign.Spacing.xs)
                }
                .buttonStyle(PlainButtonStyle())
                .help("Clear all regular tabs")
                .transition(.blur.animation(NookDesign.Motion.quick))
                .onHoverTracking { state in
                    isClearHovered = state
                }
            }
        }
        .frame(height: NookDesign.Size.rowGlyph + NookDesign.Spacing.xxs)
        .frame(maxWidth: .infinity)
    }

    private var isWaving: Bool { isOrganizing && !reduceMotion }
}

// MARK: - WaveLine

/// A horizontal rule that bends into a travelling sine wave. Both ends stay pinned to the
/// centre line, and at amplitude 0 it is a straight hairline.
private struct WaveLine: Shape {
    var amplitude: CGFloat
    var phase: CGFloat

    var animatableData: CGFloat {
        get { amplitude }
        set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        guard amplitude > 0, rect.width > 0 else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
        for x in stride(from: CGFloat(0), through: rect.width, by: 2) {
            let envelope = sin(.pi * x / rect.width)
            let wave = sin(2 * .pi * x / NookDesign.Size.waveLength - phase)
            path.addLine(to: CGPoint(x: rect.minX + x, y: rect.midY + amplitude * envelope * wave))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
 
