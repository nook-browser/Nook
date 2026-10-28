// Licensed under GPL-3.0. See LICENSE.
//
//  PortraitCaptureView.swift
//  Nook
//
//  Capture in Portrait Mode, as Arc has it: the visible page framed on the desktop wallpaper
//  (or a grained gray, or a color from the slider), marked with Nook's icon, copied as one image.
//

import AppKit
import UniformTypeIdentifiers
import SwiftUI
import NookDesign
import NookWeb
import NookUI

struct PortraitCaptureView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    let session: PageSession

    @State private var page: NSImage?
    @State private var backdrop: CaptureBackdrop = .wallpaper
    @State private var wallpaper: NSImage?
    @State private var isCapturing = false
    @State private var lastHue: Double = 0.07
    /// The last capture, kept so it can be saved after it was copied.
    @State private var captured: NSImage?

    /// The slider's hue, or where it rests while another backdrop is chosen.
    private var hue: Double? {
        if case .hue(let value) = backdrop { return value }
        return nil
    }

    private let width: CGFloat = 380
    private let previewHeight: CGFloat = 210
    private let knob: CGFloat = 16
    private let swatch: CGFloat = 30

    var body: some View {
        VStack(spacing: NookDesign.Spacing.md) {
            if captured == nil {
                Button(action: capture) {
                    Text("Capture in Portrait Mode")
                        .font(NookDesign.Font.title)
                        .frame(maxWidth: .infinity)
                        .frame(height: NookDesign.Size.row + NookDesign.Spacing.sm)
                        .background(Color.black.opacity(0.55), in: NookDesign.Radius.shape(NookDesign.Radius.md))
                        .foregroundStyle(.white)
                        .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
                }
                .buttonStyle(CapturePress())
                .disabled(page == nil || isCapturing)
                .transition(.blurReplace)
            } else {
                // Copied already; keep it for good, or carry on.
                HStack(spacing: NookDesign.Spacing.sm) {
                    Label("Copied", systemImage: "checkmark.circle.fill")
                        .font(NookDesign.Font.title)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, NookDesign.Spacing.sm)
                    Button(action: save) {
                        Label("Save…", systemImage: "square.and.arrow.down")
                            .font(NookDesign.Font.label)
                            .padding(.horizontal, NookDesign.Spacing.md)
                            .frame(height: NookDesign.Size.row)
                            .background(Color.white, in: NookDesign.Radius.shape(NookDesign.Radius.md))
                            .foregroundStyle(.black)
                            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
                    }
                    .buttonStyle(CapturePress())
                    .keyboardShortcut("s", modifiers: .command)
                    Button(action: close) {
                        Text("Done")
                            .font(NookDesign.Font.label)
                            .padding(.horizontal, NookDesign.Spacing.md)
                            .frame(height: NookDesign.Size.row)
                            .background(Color.white.opacity(0.15), in: NookDesign.Radius.shape(NookDesign.Radius.md))
                            .foregroundStyle(.white)
                            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
                    }
                    .buttonStyle(CapturePress())
                }
                .frame(height: NookDesign.Size.row + NookDesign.Spacing.sm)
                .transition(.blurReplace)
            }

            Group {
                if let page {
                    PortraitComposition(page: page, backdrop: backdrop, wallpaper: wallpaper, mark: .corner)
                } else {
                    NookDesign.Surface.fill.overlay(ProgressView().controlSize(.small))
                }
            }
            .frame(height: previewHeight)
            .frame(maxWidth: .infinity)
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
            .animation(NookDesign.Motion.standard, value: backdrop)
            .onChange(of: backdrop) { _, _ in withAnimation(NookDesign.Motion.quick) { captured = nil } }

            HStack(spacing: NookDesign.Spacing.md) {
                Button {
                    withAnimation(NookDesign.Motion.quick) { backdrop = .neutral }
                } label: {
                    Circle()
                        .fill(Color.gray)
                        .frame(width: swatch * 0.6, height: swatch * 0.6)
                        .overlay(Circle().strokeBorder(.white, lineWidth: backdrop == .neutral ? 2 : 0))
                }
                .buttonStyle(.plain)
                .help("Gray")

                hueSlider

                Button {
                    withAnimation(NookDesign.Motion.quick) { backdrop = .wallpaper }
                } label: {
                    CaptureBackdropView(backdrop: wallpaper == nil ? .hue(0.07) : .wallpaper, wallpaper: wallpaper)
                        .frame(width: swatch, height: swatch)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: backdrop == .wallpaper ? 2 : 0.5))
                }
                .buttonStyle(.plain)
                .help("Desktop Picture")
                .disabled(wallpaper == nil)
            }
        }
        .padding(NookDesign.Spacing.md)
        .frame(width: width)
        .nookFloatingSurface(in: NookDesign.Radius.shape(NookDesign.Radius.xl))
        .environment(\.colorScheme, .dark)
        .onExitCommand { close() }
        .task(id: session.itemID) {
            wallpaper = Self.desktopPicture()
            if wallpaper == nil { backdrop = .hue(0.07) }
            await snapshot()
        }
    }

    private var hueSlider: some View {
        GeometryReader { proxy in
            let travel = proxy.size.width - knob
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 8).map { Color(hue: $0, saturation: 0.75, brightness: 1) },
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: knob / 2 + 4)
                Circle()
                    .fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: travel * (hue ?? lastHue))
                    .opacity(hue == nil ? 0.4 : 1)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                guard travel > 0 else { return }
                let value = min(1, max(0, (drag.location.x - knob / 2) / travel))
                lastHue = value
                backdrop = .hue(value)
            })
        }
        .frame(height: swatch)
        .accessibilityElement()
        .accessibilityLabel("Backdrop color")
        .accessibilityAdjustableAction { direction in
            let current = hue ?? lastHue
            switch direction {
            case .increment: backdrop = .hue(min(1, current + 0.05))
            case .decrement: backdrop = .hue(max(0, current - 0.05))
            @unknown default: break
            }
        }
    }

    private func snapshot() async {
        guard let webView = session.webView else { return }
        page = try? await webView.takeSnapshot(configuration: nil)
    }

    /// The framed page at the page's own resolution: copied at once, then offered for saving.
    private func capture() {
        guard let page else { return }
        isCapturing = true
        let size = PortraitComposition.canvasSize(for: page.size)
        let renderer = ImageRenderer(content: PortraitComposition(page: page, backdrop: backdrop, wallpaper: wallpaper, mark: .footer)
            .frame(width: size.width, height: size.height))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        if let image = renderer.nsImage {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
            withAnimation(NookDesign.Motion.spring) { captured = image }
        }
        isCapturing = false
    }

    /// Straight into Downloads as Arc saves it: named for the page's title, listed with the
    /// other downloads, flown to the downloads button. A name already taken gets a number.
    private func save() {
        guard let captured, let tiff = captured.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        let title = session.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = title.isEmpty ? (session.url.host ?? "Capture") : title
        let saved = browserManager.downloadManager.saveCompletedFile(
            png, suggestedFilename: name + ".png", originalURL: session.url, from: NSApp.keyWindow,
            origin: DownloadOrigin(session: session))
        browserManager.showWindowToast(saved == nil ? "Couldn't save the capture" : "Saved to Downloads", in: windowState)
        if saved != nil { close() }
    }

    private func close() {
        withAnimation(NookDesign.Motion.spring) { windowState.isPortraitCaptureVisible = false }
    }

    /// The main screen's desktop picture, when it is an image file (a dynamic or video
    /// wallpaper may not be; the color backdrop stands in then).
    private static func desktopPicture() -> NSImage? {
        guard let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
        return NSImage(contentsOf: url)
    }
}

enum CaptureBackdrop: Equatable {
    case wallpaper
    case neutral
    /// 0...1 around the color wheel.
    case hue(Double)
}

/// The page on its backdrop: centered, rounded, lifted, with Nook's mark.
struct PortraitComposition: View {
    enum Mark {
        /// The preview: the icon alone in the corner, as Arc's preview shows its logo.
        case corner
        /// The copied image: icon and "Captured with Nook" centered at the foot.
        case footer
    }

    let page: NSImage
    let backdrop: CaptureBackdrop
    let wallpaper: NSImage?
    let mark: Mark

    /// Arc's proportions, measured off its own capture: the page takes 85.5% of the width and
    /// 80.6% of the height, so the margin is 7.25% at the sides and 9.7% above and below.
    static let horizontalMargin: CGFloat = 0.0725
    static let verticalMargin: CGFloat = 0.097

    /// The whole image for a page of `size`, so the page fills its slot with no letterboxing.
    static func canvasSize(for size: CGSize) -> CGSize {
        CGSize(width: size.width / (1 - 2 * horizontalMargin), height: size.height / (1 - 2 * verticalMargin))
    }

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width
            let radius = unit * 0.005
            let border = max(2, unit * 0.0035)
            ZStack {
                CaptureBackdropView(backdrop: backdrop, wallpaper: wallpaper)
                Image(nsImage: page)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(NookDesign.Radius.shape(radius))
                    // Arc's liquid border: a frosted rim of the backdrop's own light around the
                    // page, brighter at the top edge as if lit from above.
                    .padding(border)
                    .background {
                        NookDesign.Radius.shape(radius + border)
                            .fill(.white.opacity(0.32))
                            .overlay(
                                NookDesign.Radius.shape(radius + border)
                                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.35), .white.opacity(0.6)],
                                                                 startPoint: .top, endPoint: .bottom),
                                                  lineWidth: max(1, border * 0.35)))
                    }
                    .shadow(color: .black.opacity(0.28), radius: unit * 0.012, y: unit * 0.004)
                    .padding(.horizontal, unit * Self.horizontalMargin - border)
                    .padding(.vertical, proxy.size.height * Self.verticalMargin - border)
                switch mark {
                case .corner:
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: unit * 0.07, height: unit * 0.07)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(unit * 0.025)
                case .footer:
                    // Small and quiet, centred in the bottom margin, as Arc's mark is.
                    HStack(spacing: unit * 0.004) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: unit * 0.014, height: unit * 0.014)
                        Text("Captured with Nook")
                            .font(.system(size: max(9, unit * 0.0085), weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, proxy.size.height * Self.verticalMargin / 2 - unit * 0.007)
                }
            }
        }
    }
}

/// The desktop picture, softened and grained, or the streaked color/gray backdrop.
struct CaptureBackdropView: View {
    let backdrop: CaptureBackdrop
    let wallpaper: NSImage?

    var body: some View {
        switch backdrop {
        case .wallpaper:
            if let wallpaper {
                // Sized to the frame, never by the picture: a filled image is larger than its frame
                // and would otherwise grow the composition and push the page off its edge.
                GeometryReader { proxy in
                    Image(nsImage: wallpaper)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        // Soft like Arc's: in proportion to the size, so preview and export match.
                        // Arc keeps the picture's shapes and adds heavy grain rather than melting it.
                        .blur(radius: proxy.size.width * 0.007, opaque: true)
                        .saturation(1.15)
                        .scaleEffect(1.03)
                        .overlay { FilmGrain(opacity: 0.9) }
                        .clipped()
                }
            } else {
                PortraitBackdrop(hue: 0.07)
            }
        case .neutral:
            PortraitBackdrop(hue: nil)
        case .hue(let value):
            PortraitBackdrop(hue: value)
        }
    }
}

/// Streaks of the chosen hue over near-black, grained, like Arc's capture backdrops.
struct PortraitBackdrop: View {
    let hue: Double?

    var body: some View {
        let base = hue.map { Color(hue: $0, saturation: 0.9, brightness: 1) } ?? Color(white: 0.6)
        let light = hue.map { Color(hue: min(1, $0 + 0.05), saturation: 0.7, brightness: 1) } ?? Color(white: 0.85)
        let dark = Color(white: 0.12)
        GeometryReader { proxy in
        ZStack {
            dark
            // Bands running across, slightly tilted, brightest at the sides as Arc's are.
            LinearGradient(stops: [
                .init(color: base, location: 0), .init(color: dark, location: 0.1), .init(color: light, location: 0.2),
                .init(color: base, location: 0.26), .init(color: dark, location: 0.4), .init(color: base, location: 0.55),
                .init(color: dark, location: 0.68), .init(color: light, location: 0.8), .init(color: base, location: 0.86),
                .init(color: dark, location: 1),
            ], startPoint: UnitPoint(x: 0.42, y: 0), endPoint: UnitPoint(x: 0.58, y: 1))
            .blur(radius: proxy.size.width * 0.03)
            .scaleEffect(1.2)
            // The middle sinks back behind the page.
            RadialGradient(colors: [dark.opacity(0.75), .clear], center: .center, startRadius: 0, endRadius: proxy.size.width * 0.7)
            FilmGrain(opacity: 0.9)
        }
        .frame(width: proxy.size.width, height: proxy.size.height)
        .clipped()
        }
    }
}

private struct CapturePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(NookDesign.Motion.quick, value: configuration.isPressed)
    }
}
