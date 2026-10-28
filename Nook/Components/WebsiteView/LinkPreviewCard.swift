// Licensed under GPL-3.0. See LICENSE.
//
//  LinkPreviewCard.swift
//  Nook
//
//  The Link Previews card, as Arc draws it: the page's image, a one-line headline, four facts
//  each with a symbol, and a share button. It appears under a link while Shift is held over it
//  and stays while the pointer is on it, so it can be read and shared.
//

import AppKit
import SwiftUI
import NookDesign
import NookWeb
import NookUI

/// Decides what shows: the link Shift is held over, kept a moment after the pointer leaves it so
/// the pointer can travel onto the card, and for as long as it rests there.
struct LinkPreviewHost: View {
    let session: PageSession
    let zoom: CGFloat

    @State private var shown: LinkPreviewTarget?
    @State private var isOnCard = false
    @State private var hideTask: Task<Void, Never>?

    private let linger: Duration = .milliseconds(300)

    var body: some View {
        ZStack {
            if let shown {
                LinkPreviewOverlay(target: shown, zoom: zoom) { hovering in
                    isOnCard = hovering
                    if !hovering { scheduleHide() }
                }
                .id(shown.url)
            }
        }
        .onChange(of: session.linkPreview, initial: true) { _, target in
            if let target {
                hideTask?.cancel()
                withAnimation(NookDesign.Motion.quick) { shown = target }
            } else {
                scheduleHide()
            }
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: linger)
            guard !Task.isCancelled, !isOnCard, session.linkPreview == nil else { return }
            withAnimation(NookDesign.Motion.quick) { shown = nil }
        }
    }
}

private struct LinkPreviewOverlay: View {
    let target: LinkPreviewTarget
    /// Page zoom: the link's box arrives in CSS pixels.
    let zoom: CGFloat
    let onHover: (Bool) -> Void

    private let width: CGFloat = 340
    private let gap: CGFloat = NookDesign.Spacing.sm

    var body: some View {
        GeometryReader { proxy in
            let link = CGRect(x: target.rect.minX * zoom, y: target.rect.minY * zoom,
                              width: target.rect.width * zoom, height: target.rect.height * zoom)
            // Under the link when the lower half has room, else above it.
            let below = link.maxY < proxy.size.height * 0.55
            let x = min(max(link.minX, NookDesign.Spacing.md), max(NookDesign.Spacing.md, proxy.size.width - width - NookDesign.Spacing.md))
            LinkPreviewCard(url: target.url, style: .live)
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .onHoverTracking { onHover($0) }
                .alignmentGuide(.top) { dimensions in below ? -(link.maxY + gap) : -(link.minY - gap - dimensions.height) }
                .alignmentGuide(.leading) { _ in -x }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: below ? .top : .bottom)))
        }
        .task(id: target.url) { LinkPreviewService.shared.load(target.url) }
    }
}

struct LinkPreviewCard: View {
    enum Style {
        /// On screen, with the share button.
        case live
        /// Copy as Image: a footer with the site in place of the button.
        case shared
    }

    let url: URL
    let style: Style

    private let imageHeight: CGFloat = 170
    private let symbolWidth: CGFloat = 22
    private let shareSize: CGFloat = 32
    private let photoInset: CGFloat = 3
    /// Arc's copied card is 456 pt wide.
    private static let sharedWidth: CGFloat = 456

    private var service: LinkPreviewService { .shared }
    private var state: LinkPreviewService.State? { service.state(for: url) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Arc's photo runs to the card's edges: a hair of inset, its own rounding inside.
            if let image = service.images[url] {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: imageHeight)
                    .frame(maxWidth: .infinity)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.lg - photoInset))
                    .padding([.horizontal, .top], photoInset)
                    .transition(.opacity)
            }
            VStack(alignment: .leading, spacing: NookDesign.Spacing.sm) {
                content
            }
            .padding(.horizontal, NookDesign.Spacing.xl)
            .padding(.top, NookDesign.Spacing.lg)
            .padding(.bottom, NookDesign.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)

            if style == .shared { footer }
        }
        .overlay(alignment: .bottomTrailing) {
            if style == .live, case .ready = state { shareButton.padding(NookDesign.Spacing.md) }
        }
        .background(NookDesign.Surface.previewCard)
        // On screen a rounded floating card; the copied image is a plain rectangle, as Arc's is.
        .clipShape(NookDesign.Radius.shape(style == .live ? NookDesign.Radius.lg : 0))
        .overlay(NookDesign.Radius.shape(NookDesign.Radius.lg).strokeBorder(NookDesign.Surface.hairline).opacity(style == .live ? 1 : 0))
        .nookElevation(style == .live ? .floating : .flat)
        .animation(NookDesign.Motion.standard, value: state)
        .animation(NookDesign.Motion.standard, value: service.images[url] != nil)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch state {
        case .ready(let preview):
            if let summary = preview.summary {
                Text(summary.headline.isEmpty ? (preview.page.title ?? "") : summary.headline)
                    .font(NookDesign.Font.title)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, NookDesign.Spacing.xxs)
                ForEach(summary.points, id: \.self) { point in
                    HStack(alignment: .firstTextBaseline, spacing: NookDesign.Spacing.md) {
                        // Arc's symbols are hairline and quiet; the words carry the weight.
                        Image(systemName: point.symbol)
                            .fontWeight(.light)
                            .foregroundStyle(.tertiary)
                            .frame(width: symbolWidth)
                        (Text(point.label + ": ").fontWeight(.bold) + Text(point.detail))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(NookDesign.Font.title.weight(.regular))
                }
            } else {
                if let title = preview.page.title {
                    Text(title)
                        .font(NookDesign.Font.title)
                        .lineLimit(2)
                }
                if let description = preview.page.description {
                    Text(description)
                        .font(NookDesign.Font.bodyRegular)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                if preview.isSummarizing {
                    ShimmerLines()
                }
            }
            // Room for the share button under the last line.
            if style == .live { Color.clear.frame(height: shareSize - NookDesign.Spacing.md) }
        case .failed:
            Text(url.host ?? url.absoluteString)
                .font(NookDesign.Font.title)
            Text("No preview for this page")
                .font(NookDesign.Font.bodyRegular)
                .foregroundStyle(.secondary)
        case .loading, nil:
            ShimmerLines()
        }
    }

    /// Arc's footer on the copied image: a dashed rule, then the landed site and the browser's name
    /// on a pale lavender band.
    private var footer: some View {
        let landed: URL? = { if case .ready(let preview) = state { return preview.page.landedURL } ; return nil }()
        let host = (landed ?? url).host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
        return HStack(spacing: NookDesign.Spacing.md) {
            if let icon = service.icons[url] {
                Image(platformImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: NookDesign.Size.essentialsFavicon, height: NookDesign.Size.essentialsFavicon)
                    .foregroundStyle(.secondary)
            }
            Text(host)
                .foregroundStyle(Self.footerInk)
            Spacer()
            Text("Nook")
                .fontWeight(.bold)
                .foregroundStyle(Self.footerInk)
        }
        .font(NookDesign.Font.title.weight(.medium))
        .padding(.horizontal, NookDesign.Spacing.xl)
        .padding(.vertical, NookDesign.Spacing.lg)
        .background(Self.footerBand)
        .overlay(alignment: .top) {
            Rectangle()
                .stroke(Self.footerRule, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .frame(height: 0.75)
        }
    }

    // The copied image is always light, as Arc's is; these are its footer's fixed colors.
    private static let footerBand = Color(red: 0.96, green: 0.96, blue: 0.99)
    private static let footerRule = Color(red: 0.84, green: 0.83, blue: 0.95)
    private static let footerInk = Color(red: 0.58, green: 0.57, blue: 0.66)

    // MARK: Share

    private var shareButton: some View {
        Menu {
            Button("Copy as Text", systemImage: "doc.on.doc", action: copyText)
            Button("Copy as Image", systemImage: "photo.on.rectangle", action: copyImage)
            Button("Messages", systemImage: "message") {
                NSSharingService(named: .composeMessage)?.perform(withItems: [url])
            }
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: NookDesign.Size.spaceIcon, weight: .medium))
                .frame(width: shareSize, height: shareSize)
                .background(NookDesign.Surface.fillPressed, in: Circle())
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Share")
    }

    private func copyText() {
        guard case .ready(let preview) = state else { return }
        var lines: [String] = []
        if let summary = preview.summary {
            lines.append(summary.headline)
            lines += summary.points.map { "• \($0.label): \($0.detail)" }
        } else {
            lines += [preview.page.title, preview.page.description].compactMap { $0 }
        }
        lines.append(url.absoluteString)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    /// The card as Arc shares it: light, with the site in a footer.
    private func copyImage() {
        let renderer = ImageRenderer(content: LinkPreviewCard(url: url, style: .shared)
            .frame(width: Self.sharedWidth)
            .environment(\.colorScheme, .light))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}

/// Placeholder lines while the page loads or the model writes.
private struct ShimmerLines: View {
    @State private var phase = false

    var body: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.sm) {
            ForEach([0.9, 0.75, 0.82, 0.6], id: \.self) { fraction in
                GeometryReader { proxy in
                    NookDesign.Radius.shape(NookDesign.Radius.sm)
                        .fill(NookDesign.Surface.fillPressed)
                        .frame(width: proxy.size.width * fraction)
                }
                .frame(height: NookDesign.Spacing.md)
            }
        }
        .opacity(phase ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: phase)
        .onAppear { phase = true }
        .accessibilityLabel("Loading preview")
    }
}
