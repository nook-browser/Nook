// Licensed under GPL-3.0. See LICENSE.
//
//  DownloadPreviewOverlay.swift
//  Nook
//
//  A download opened in place, as Arc does: the file in a Quick Look card over the window,
//  arrows to step through recent downloads, and Open in its own app one click away.
//

import AppKit
import PDFKit
import Quartz
import UniformTypeIdentifiers
import SwiftUI
import NookDesign
import NookUI

extension DownloadManager {
    /// Finished downloads still on disk, newest first: what the preview steps through.
    var previewable: [Download] {
        allDownloads.filter { $0.completedFile != nil }
    }
}

struct DownloadPreviewOverlay: View {
    let downloads: DownloadManager
    let download: Download

    @State private var appeared = false

    private let maxWidth: CGFloat = 1100
    private let headerHeight: CGFloat = 52

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(appeared ? 0.45 : 0)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)

                // Arc's lightbox: the file on a pale gray field under a gray bar, in any appearance.
                VStack(spacing: 0) {
                    header
                        .background(Color(white: 0.55).opacity(0.92))
                        .environment(\.colorScheme, .dark)
                    Group {
                        if isPDF, let file = download.completedFile {
                            PDFDocumentView(url: file)
                        } else {
                            QuickLookView(url: download.completedFile)
                        }
                    }
                    .padding(.vertical, NookDesign.Spacing.lg)
                }
                .background(RadialGradient(colors: [Color(white: 0.97), Color(white: 0.84)],
                                           center: .center, startRadius: 0, endRadius: 900))
                .frame(width: min(maxWidth, proxy.size.width * 0.8), height: proxy.size.height * 0.78)
                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xl))
                .nookElevation(.floating)
                // Opacity and a short rise only: blur or scale on this card flattens the AppKit
                // viewer inside it into a picture, which then takes no scrolling or clicks.
                .offset(y: appeared ? 0 : 12)
                .opacity(appeared ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.interpolatingSpring(Spring(response: 0.32, dampingRatio: 0.88))) { appeared = true }
        }
        .onExitCommand(perform: close)
    }

    private var header: some View {
        let list = downloads.previewable
        let index = list.firstIndex { $0 === download }
        return HStack(spacing: NookDesign.Spacing.sm) {
            Button("Close", systemImage: "xmark", action: close)
                .keyboardShortcut(.cancelAction)
            Button("Previous", systemImage: "chevron.left") { step(-1, in: list, from: index) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(index.map { $0 <= 0 } ?? true)
            Button("Next", systemImage: "chevron.right") { step(1, in: list, from: index) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(index.map { $0 >= list.count - 1 } ?? true)

            Text(download.displayName)
                .font(NookDesign.Font.title)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, NookDesign.Spacing.xs)
                .id(download.id)
                .transition(.blurReplace)
            Text(download.startDate.formatted(.relative(presentation: .named, unitsStyle: .wide)))
                .font(NookDesign.Font.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: NookDesign.Spacing.lg)

            Menu {
                Button("Show in Finder", systemImage: "folder") {
                    if let file = download.completedFile { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                }
                Button("Copy", systemImage: "doc.on.doc") {
                    if let file = download.completedFile {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([file as NSURL])
                    }
                }
                Divider()
                Button("Move to Trash", systemImage: "trash") {
                    close()
                    downloads.moveToTrash(download)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()

            Button {
                openExternally()
                close()
            } label: {
                Label(openTitle, systemImage: "arrow.up.forward")
                    .labelStyle(TitleThenIcon())
                    .font(NookDesign.Font.label)
                    .padding(.horizontal, NookDesign.Spacing.md)
                    .frame(height: NookDesign.Size.iconButton)
                    .background(Color.white.opacity(0.18), in: NookDesign.Radius.shape(NookDesign.Radius.md))
                    .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
            }
            .buttonStyle(.plain)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(NookIconButtonStyle())
        .padding(.horizontal, NookDesign.Spacing.md)
        .frame(height: headerHeight)
        .animation(NookDesign.Motion.quick, value: download.id)
    }

    private var isPDF: Bool {
        download.completedFile.flatMap { UTType(filenameExtension: $0.pathExtension) }?.conforms(to: .pdf) ?? false
    }

    private static let previewApp = URL(fileURLWithPath: "/System/Applications/Preview.app")

    /// Preview for what it shows (PDFs and images), as on a Mac; else the file's own app.
    private var opensInPreview: Bool {
        guard let type = download.completedFile.flatMap({ UTType(filenameExtension: $0.pathExtension) }) else { return false }
        return type.conforms(to: .pdf) || type.conforms(to: .image)
    }

    private var openTitle: String {
        if opensInPreview { return "Open in Preview" }
        guard let file = download.completedFile, let app = NSWorkspace.shared.urlForApplication(toOpen: file) else { return "Open" }
        return "Open in " + FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    private func openExternally() {
        guard let file = download.completedFile else { return }
        if opensInPreview {
            NSWorkspace.shared.open([file], withApplicationAt: Self.previewApp, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(file)
        }
    }

    private func step(_ by: Int, in list: [Download], from index: Int?) {
        guard let index, list.indices.contains(index + by) else { return }
        downloads.previewing = list[index + by]
    }

    private func close() {
        withAnimation(.interpolatingSpring(Spring(response: 0.25, dampingRatio: 1))) { appeared = false }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            downloads.previewing = nil
        }
    }
}

private struct TitleThenIcon: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: NookDesign.Spacing.xs) {
            configuration.title
            configuration.icon
        }
    }
}

/// PDFKit's viewer: scrolls, zooms, selects text and follows links, which Quick Look's does not.
private struct PDFDocumentView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.pageShadowsEnabled = true
        // The lightbox's own gray shows around the page.
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}

/// macOS's Quick Look view: previews any other file it has a previewer for.
private struct QuickLookView: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        view.autostarts = true
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? NSURL) as URL? != url {
            view.previewItem = url as NSURL?
        }
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.close()
    }
}
