//
//  SafariImportFlow.swift
//  Nook
//
//  Created by Maciek Bagiński on 20/02/2026.
//

import SwiftUI
import UniformTypeIdentifiers

enum SafariImportState {
    case picking
    case previewing
    case importing
    case done
}

struct SafariImportFlow: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Binding var isLoading: Bool
    var onBack: () -> Void
    var onComplete: () -> Void

    @State private var state: SafariImportState = .picking
    @State private var exportContents: SafariExportContents?
    @State private var importBookmarks: Bool = true
    @State private var importHistory: Bool = true
    @State private var errorMessage: String?
    @State private var importedBookmarkCount: Int = 0
    @State private var importedHistoryCount: Int = 0
    @State private var isDropTargeted: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Import from Safari")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)

            contentView
        }
        .transition(.slideAndBlur)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.return) {
            handleReturn()
        }
    }

    private func handleReturn() -> KeyPress.Result {
        guard !isLoading else { return .ignored }
        switch state {
        case .previewing:
            if importBookmarks || importHistory {
                startImport()
                return .handled
            }
        case .done:
            onComplete()
            return .handled
        default:
            break
        }
        return .ignored
    }

    // MARK: - Content switcher

    @ViewBuilder
    private var contentView: some View {
        switch state {
        case .picking:
            pickingView
                .transition(.slideAndBlur)
        case .previewing:
            previewView
                .transition(.slideAndBlur)
        case .importing:
            importingView
                .transition(.slideAndBlur)
        case .done:
            doneView
                .transition(.slideAndBlur)
        }
    }

    // MARK: - Picking: Instructions

    @ViewBuilder
    private var pickingView: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 16) {
                instructionRow(number: "1", text: "Open Safari")
                instructionRow(number: "2", text: "In the menu bar, go to **File \u{2192} Export Browsing Data\u{2026}**")
                instructionRow(number: "3", text: "Choose what you want to export")
                instructionRow(number: "4", text: "Save the zip file anywhere on your Mac")
            }
            .padding(24)
            .background(.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                        )
                        .foregroundStyle(isDropTargeted ? .white : .white.opacity(0.4))
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isDropTargeted ? .white.opacity(0.15) : .white.opacity(0.05))
                        )
                        .animation(.easeInOut(duration: 0.15), value: isDropTargeted)

                    VStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(.white.opacity(0.6))

                        Text("Drop export here")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))

                        Text("or")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.5))

                        Button {
                            openFolderPicker()
                        } label: {
                            Text("Choose Folder")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(ScaleButtonStyle())
                    }
                }
                .frame(width: 180, height: 180)
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers: providers)
                    return true
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .frame(width: 180)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)

        Button {
            onBack()
        } label: {
            Text("Back")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.8))
                .padding(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewView: some View {
        if let contents = exportContents {
            VStack(spacing: 12) {
                if contents.hasBookmarks {
                    toggleRow(
                        icon: "bookmark.fill",
                        label: "\(contents.bookmarkCount) bookmark\(contents.bookmarkCount == 1 ? "" : "s")",
                        isOn: $importBookmarks
                    )
                }
                if contents.hasHistory {
                    toggleRow(
                        icon: "clock.fill",
                        label: "\(contents.historyCount) history entr\(contents.historyCount == 1 ? "y" : "ies")",
                        isOn: $importHistory
                    )
                }
            }
            .padding(20)
            .background(.white.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .fixedSize(horizontal: true, vertical: true)

            HStack(spacing: 12) {
                Button {
                    startImport()
                } label: {
                    HStack(spacing: 8) {
                        Text("Import")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                        Image(systemName: "return")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.8))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(ScaleButtonStyle())
                .disabled(!importBookmarks && !importHistory)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        exportContents = nil
                        errorMessage = nil
                        state = .picking
                    }
                } label: {
                    Text("Back")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Importing

    @ViewBuilder
    private var importingView: some View {
        VStack(spacing: 16) {
            RoundedSpinner()
                .frame(width: 32, height: 32)

            Text("This may take a moment...")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Done

    @ViewBuilder
    private var doneView: some View {
        VStack(spacing: 12) {
            if importedBookmarkCount > 0 {
                summaryRow(icon: "bookmark.fill", label: "\(importedBookmarkCount) bookmark\(importedBookmarkCount == 1 ? "" : "s") imported")
            }
            if importedHistoryCount > 0 {
                summaryRow(icon: "clock.fill", label: "\(importedHistoryCount) history entr\(importedHistoryCount == 1 ? "y" : "ies") imported")
            }
            if importedBookmarkCount == 0 && importedHistoryCount == 0 {
                summaryRow(icon: "checkmark.circle.fill", label: "Nothing new to import")
            }
        }
        .padding(20)
        .background(.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .fixedSize(horizontal: true, vertical: true)

        Button {
            onComplete()
        } label: {
            HStack(spacing: 8) {
                Text("Continue")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                Image(systemName: "return")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 24)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Shared components

    @ViewBuilder
    private func instructionRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 24, height: 24)
                .background(.white)
                .clipShape(Circle())

            Text(.init(text))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    @ViewBuilder
    private func toggleRow(icon: String, label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 20)

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
        }
    }

    @ViewBuilder
    private func summaryRow(icon: String, label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.green)
                .frame(width: 20)

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Actions

    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your Safari Export folder"
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            validateAndLoad(url: url)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        guard let provider = providers.first else { return }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Could not read the dropped item."
                }
                return
            }
            DispatchQueue.main.async {
                validateAndLoad(url: url)
            }
        }
    }

    private func validateAndLoad(url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            withAnimation(.easeInOut(duration: 0.25)) {
                errorMessage = "Please select a folder, not a file."
            }
            return
        }

        if let contents = browserManager.importManager.checkSafariExport(at: url) {
            withAnimation(.easeInOut(duration: 0.25)) {
                exportContents = contents
                errorMessage = nil
                state = .previewing
            }
        } else {
            withAnimation(.easeInOut(duration: 0.25)) {
                errorMessage = "Not a valid Safari export folder."
            }
        }
    }

    private func startImport() {
        withAnimation(.easeInOut(duration: 0.25)) {
            state = .importing
            isLoading = true
        }

        guard let contents = exportContents else { return }

        Task {
            await browserManager.importSafariData(
                from: contents.directoryURL,
                importBookmarks: importBookmarks,
                importHistory: importHistory
            )

            await MainActor.run {
                importedBookmarkCount = importBookmarks ? contents.bookmarkCount : 0
                importedHistoryCount = importHistory ? contents.historyCount : 0
                isLoading = false
                withAnimation(.easeInOut(duration: 0.25)) {
                    state = .done
                }
            }
        }
    }
}
