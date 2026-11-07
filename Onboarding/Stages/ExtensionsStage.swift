// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionsStage.swift
//  Nook
//

import NookDesign
import SwiftUI

struct ExtensionsStage: View {
    let choices: [ExtensionChoice]
    let onDone: ([ExtensionOffer]) -> Void

    @State private var selection: ExtensionSelection

    init(choices: [ExtensionChoice], onDone: @escaping ([ExtensionOffer]) -> Void) {
        self.choices = choices
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

            ExtensionChoiceList(choices: choices, selection: $selection)
                .padding(20)
                .frame(width: 400)
                .background(.white.opacity(0.1))
                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.lg))

            HStack(spacing: 12) {
                Button {
                    onDone(selection.chosen(from: choices))
                } label: {
                    HStack(spacing: 8) {
                        Text(selection.installTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.black)
                        Image(systemName: "return")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.black.opacity(0.8))
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(.white)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
                }
                .buttonStyle(ScaleButtonStyle())
                .keyboardShortcut(.defaultAction)

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
