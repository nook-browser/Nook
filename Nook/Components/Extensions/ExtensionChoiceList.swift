// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionChoiceList.swift
//  Nook
//

import AppKit
import NookDesign
import SwiftUI

/// Which choices are checked, and which version is picked where there are two.
struct ExtensionSelection {
    private(set) var included: Set<String>
    private var picked: [String: String] = [:]

    init(_ choices: [ExtensionChoice]) {
        included = Set(choices.map(\.id))
    }

    var count: Int { included.count }

    var installTitle: String {
        switch count {
        case 0: "Continue"
        case 1: "Install 1 extension"
        default: "Install \(count) extensions"
        }
    }

    func version(of choice: ExtensionChoice) -> ExtensionOffer {
        choice.versions.first { $0.id == picked[choice.id] } ?? choice.versions[0]
    }

    func chosen(from choices: [ExtensionChoice]) -> [ExtensionOffer] {
        choices.filter { included.contains($0.id) }.map(version(of:))
    }

    mutating func set(_ choice: ExtensionChoice, included isIncluded: Bool) {
        if isIncluded {
            included.insert(choice.id)
        } else {
            included.remove(choice.id)
        }
    }

    mutating func pick(_ offerID: String, for choice: ExtensionChoice) {
        picked[choice.id] = offerID
    }
}

struct ExtensionChoiceList: View {
    let choices: [ExtensionChoice]
    @Binding var selection: ExtensionSelection
    @State private var hasMoreBelow = false

    static func subtitle(for choices: [ExtensionChoice]) -> String {
        let versions = choices.flatMap(\.versions)
        switch (versions.contains { !$0.isSafari }, versions.contains(where: \.isSafari)) {
        case (true, true): return "Nook installs these from the Chrome Web Store and from apps on this Mac."
        case (false, _): return "Nook installs these from apps on this Mac."
        case (true, false): return "Nook installs these from the Chrome Web Store."
        }
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            rows
            ScrollView {
                rows
            }
            .scrollIndicators(.visible)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height < geometry.contentSize.height - 1
            } action: { _, hasMore in
                hasMoreBelow = hasMore
            }
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, hasMoreBelow ? .clear : .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 48)
                }
            }
        }
        .frame(maxHeight: 440)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.md) {
            ForEach(choices) { choice in
                row(choice)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ choice: ExtensionChoice) -> some View {
        let version = selection.version(of: choice)
        let isIncluded = Binding(
            get: { selection.included.contains(choice.id) },
            set: { selection.set(choice, included: $0) }
        )
        let toggle = { isIncluded.wrappedValue.toggle() }
        return HStack(alignment: .top, spacing: NookDesign.Spacing.md) {
            Toggle("Install", isOn: isIncluded)
                .toggleStyle(.checkbox)
                .labelsHidden()

            Group {
                if let icon = version.icon {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
            .onTapGesture(perform: toggle)

            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text(version.name)
                    .font(NookDesign.Font.label)
                    .lineLimit(1)
                    .onTapGesture(perform: toggle)
                if choice.versions.count > 1 {
                    Picker(
                        "Version",
                        selection: Binding(get: { version.id }, set: { selection.pick($0, for: choice) })
                    ) {
                        ForEach(choice.versions) { offer in
                            Text(offer.source.name).tag(offer.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
                Text(subtitle(choice, version: version))
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .onTapGesture(perform: toggle)
            }
        }
    }

    private func subtitle(_ choice: ExtensionChoice, version: ExtensionOffer) -> String {
        let summary = version.source.summary(version: version.version)
        return choice.versions.count > 1 ? "\(summary) · only one version can be installed" : summary
    }
}
