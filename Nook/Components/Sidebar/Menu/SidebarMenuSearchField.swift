// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarMenuSearchField.swift
//  Nook
//

import SwiftUI
import NookDesign

/// The history and downloads search field: a glass capsule the height of the sidebar's controls.
struct SidebarMenuSearchField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: NookDesign.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(NookDesign.Font.body)
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(NookDesign.Font.secondary)
                .foregroundStyle(.primary)
                .focused($isFocused)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, NookDesign.Spacing.lg)
        .frame(height: NookDesign.Size.glassControl)
        .frame(maxWidth: .infinity)
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
        .nookControlGlass(in: Capsule())
    }
}
