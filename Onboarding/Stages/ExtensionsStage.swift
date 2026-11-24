// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionsStage.swift
//  Nook
//

import NookDesign
import SwiftUI

struct ExtensionsStage: View {
    let choices: [ExtensionChoice]
    let preview: @MainActor (ExtensionOffer) async -> ExtensionConsentPreview?
    let onDone: ([ExtensionOffer]) -> Void

    @State private var selection: ExtensionSelection

    init(
        choices: [ExtensionChoice],
        preview: @escaping @MainActor (ExtensionOffer) async -> ExtensionConsentPreview?,
        onDone: @escaping ([ExtensionOffer]) -> Void
    ) {
        self.choices = choices
        self.preview = preview
        self.onDone = onDone
        _selection = State(initialValue: ExtensionSelection(choices))
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Bring your extensions")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text(ExtensionChoiceList.subtitle(for: choices))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            ExtensionChoiceList(choices: choices, selection: $selection, preview: preview)
                .padding(20)
                .frame(width: 400)
                .background(.white.opacity(0.1))
                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.lg))

            HStack(spacing: 12) {
                Button {
                    onDone(selection.chosen(from: choices))
                } label: {
                    Text(selection.installTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                        .background(.white)
                        .clipShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
                }
                .buttonStyle(ScaleButtonStyle())

                Button {
                    onDone([])
                } label: {
                    Text("Skip")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(12)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
