// Licensed under GPL-3.0. See LICENSE.
//
//  AddressField.swift
//  NookiOS
//
//  The URL field alone. It shows the host centred while idle and the full URL
//  left-aligned while editing, the way every phone browser does, so the bar
//  stays readable at thumb distance.
//

import SwiftUI
import NookDesign
import NookWeb

struct AddressField: View {
    let session: PageSession?
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let onSubmit: () -> Void

    /// What the field shows when it is not being edited.
    private var idleText: String {
        guard let url = session?.url else { return "" }
        return url.host() ?? url.absoluteString
    }

    var body: some View {
        HStack(spacing: NookDesign.Spacing.xs) {
            TextField("Search or enter address", text: $text)
                .focused($isFocused)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit(onSubmit)
                .multilineTextAlignment(isFocused ? .leading : .center)
                .foregroundStyle(.primary)

            if !isFocused, let session {
                Button {
                    if session.isLoading {
                        session.stop()
                    } else {
                        session.refresh()
                    }
                } label: {
                    Image(systemName: session.isLoading ? "xmark" : "arrow.clockwise")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(width: NookDesign.Size.rowButton)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, NookDesign.Spacing.rowPadding)
        .frame(height: NookDesign.Size.row)
        .background(NookDesign.Surface.fill, in: NookDesign.Radius.shape(NookDesign.Radius.md))
        .onChange(of: isFocused) { _, focused in
            // Editing starts on the whole URL and ends back on the host.
            text = focused ? (session?.url.absoluteString ?? "") : idleText
        }
        .onChange(of: session?.url) { _, _ in
            guard !isFocused else { return }
            text = idleText
        }
        .onAppear { text = idleText }
    }
}
