// Licensed under GPL-3.0. See LICENSE.
//
//  DialogHost.swift
//  NookiOS
//
//  The three TabActions dialogs. The Mac presents floating cards through
//  DialogManager; the phone uses alerts, which is what these three are: two
//  short text prompts and a destructive confirmation.
//
//  An alert cannot come up underneath a sheet, and all three are reachable both
//  from the root (long-press a space dot) and from inside a sheet, so the host
//  is attached in both places and `enabled` decides which one is on top.
//

import SwiftUI
import NookDesign
import NookUI

struct DialogHost: ViewModifier {
    let enabled: Bool
    @EnvironmentObject private var model: BrowserModel
    @State private var text = ""

    private func binding(_ match: @escaping (ChromeDialog) -> Bool) -> Binding<Bool> {
        Binding(
            get: { enabled && model.dialog.map(match) == true },
            set: { if !$0 { model.dismissDialog() } }
        )
    }

    private var editing: Binding<Bool> {
        binding { if case .editPinnedURL = $0 { true } else { false } }
    }

    private var creating: Binding<Bool> {
        binding { if case .createSpace = $0 { true } else { false } }
    }

    private var deleting: Binding<Bool> {
        binding { if case .deleteSpace = $0 { true } else { false } }
    }

    func body(content: Content) -> some View {
        content
            .alert("Edit Pinned URL", isPresented: editing) {
                TextField("URL", text: $text)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) { model.dismissDialog() }
                Button("Save") {
                    if case let .editPinnedURL(_, _, onSave) = model.dialog,
                       let url = URL(string: text) {
                        onSave(url)
                    }
                    model.dismissDialog()
                }
            } message: {
                if case let .editPinnedURL(_, title, _) = model.dialog {
                    Text(title)
                }
            }
            .alert("New Space", isPresented: creating) {
                TextField("Name", text: $text)
                Button("Cancel", role: .cancel) { model.dismissDialog() }
                Button("Create") {
                    if case let .createSpace(onCreate) = model.dialog {
                        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        // An alert cannot hold a colour picker, so a new space takes
                        // the default accent and Settings > Spaces edits it inline.
                        onCreate(name.isEmpty ? "New Space" : name, SpaceAccent.defaultHex)
                    }
                    model.dismissDialog()
                }
            }
            .alert("Delete Space", isPresented: deleting) {
                Button("Cancel", role: .cancel) { model.dismissDialog() }
                Button("Delete", role: .destructive) {
                    if case let .deleteSpace(_, _, _, onDelete) = model.dialog { onDelete() }
                    model.dismissDialog()
                }
            } message: {
                if case let .deleteSpace(name, count, _, _) = model.dialog {
                    Text("\(name) and its \(count) tab\(count == 1 ? "" : "s") will be deleted.")
                }
            }
            .onChange(of: model.dialog?.id) { _, _ in
                // Each prompt starts from its own value, never the last one's.
                if case let .editPinnedURL(url, _, _) = model.dialog {
                    text = url.absoluteString
                } else {
                    text = ""
                }
            }
    }
}

extension View {
    /// `enabled` is false for the copy attached behind a sheet, so only the
    /// topmost host answers a dialog.
    func dialogHost(enabled: Bool = true) -> some View {
        modifier(DialogHost(enabled: enabled))
    }
}
