// Licensed under GPL-3.0. See LICENSE.
//
//  LookupProgressView.swift
//  Nook
//
//  What a tab shows while Look It Up works on its page: the request, the stage, the sites
//  being read and a way to stop. Native, so the page under it can neither draw nor press it.
//

import SwiftUI
import NookDesign
import NookUI
import NookWeb

struct LookupProgressView: View {
    let session: PageSession

    @Environment(LookupManager.self) private var lookups
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The text keeps a reading width however wide the page is.
    private static let textWidth: CGFloat = 420, margin: CGFloat = 32

    var body: some View {
        if let stage = lookups.stage(forPage: session.url) {
            let hosts = lookups.hosts(forPage: session.url)
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xl) {
                Text(lookups.request(forPage: session.url) ?? "")
                    .font(NookDesign.Font.titleLarge)
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)
                wave
                VStack(alignment: .leading, spacing: NookDesign.Spacing.md) {
                    line("Searching the web", current: stage == .searching)
                    if !hosts.isEmpty {
                        line(hosts.count == 1 ? "Reading 1 page" : "Reading \(hosts.count) pages", current: stage != .writing)
                        VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                            ForEach(Array(hosts.enumerated()), id: \.offset) { _, host in
                                Text(host)
                                    .font(NookDesign.Font.bodyRegular)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.leading, NookDesign.Spacing.lg)
                    }
                    if stage == .writing {
                        line("Writing your page", current: true)
                    }
                }
                // No Return shortcut: it would take Return from the address bar.
                Button("Stop") { lookups.stop(page: session.url) }
                    .buttonStyle(RectNavButtonStyle())
                    .fixedSize()
            }
            .frame(maxWidth: Self.textWidth, alignment: .leading)
            .padding(Self.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
            .animation(NookDesign.Motion.settle, value: stage)
        }
    }

    private func line(_ text: String, current: Bool) -> some View {
        Text(text)
            .font(NookDesign.Font.body)
            .foregroundStyle(current ? .primary : .secondary)
    }

    /// The rule that ripples while a model works, as the sidebar's separator does for the tab
    /// organizer. Reduce Motion leaves it a still rule.
    private var wave: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            WaveLine(
                amplitude: reduceMotion ? 0 : NookDesign.Size.waveAmplitude,
                phase: timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: NookDesign.Motion.wavePeriod)
                    / NookDesign.Motion.wavePeriod * 2 * .pi
            )
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: NookDesign.Size.hairlineWidth, lineCap: .round))
        }
        .frame(height: NookDesign.Size.waveAmplitude * 4)
        .accessibilityHidden(true)
    }
}
