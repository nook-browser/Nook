// Licensed under GPL-3.0. See LICENSE.
//
//  RemoteTabSuggestionItem.swift
//  Nook
//
//  A tab open on one of the user's other Macs, published through iCloud sync.
//  Selecting it opens the URL here; the trailing label names the device.
//

import SwiftUI
import NookDesign
import NookWeb
import NookUI

struct RemoteTabSuggestionItem: View {
    let tab: SearchManager.RemoteTabMatch
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 9) {
                ZStack {
                    Image(systemName: "laptopcomputer")
                        .font(NookDesign.Font.label)
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                }
                .frame(width: 24, height: 24)
                .background(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(NookDesign.Surface.fill))
                .clipShape(
                    NookDesign.Radius.shape(NookDesign.Radius.xs)
                )
                Text(tab.title)
                    .font(NookDesign.Font.label)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Text(tab.deviceName)
                .font(NookDesign.Font.secondary)
                .foregroundStyle(isSelected ? .white : .secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
