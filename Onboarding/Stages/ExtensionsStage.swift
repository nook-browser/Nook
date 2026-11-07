// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionsStage.swift
//  Nook
//

import NookDesign
import SwiftUI

struct ExtensionsStage: View {
    let offers: [ExtensionOffer]
    let onDone: ([ExtensionOffer]) -> Void

    @State private var selected: Set<String>

    init(offers: [ExtensionOffer], onDone: @escaping ([ExtensionOffer]) -> Void) {
        self.offers = offers
        self.onDone = onDone
        _selected = State(initialValue: Set(offers.map(\.id)))
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Bring your extensions")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                Text(offers.contains(where: \.isSafari)
                     ? "Nook installs these from apps on this Mac."
                     : "Nook installs these from the Chrome Web Store.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }

            ExtensionOfferList(offers: offers, selected: $selected)
                .padding(20)
                .frame(width: 360)
                .background(.white.opacity(0.1))
                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.lg))

            HStack(spacing: 12) {
                Button {
                    onDone(offers.filter { selected.contains($0.id) })
                } label: {
                    HStack(spacing: 8) {
                        Text(ExtensionOfferList.installTitle(count: selected.count))
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
