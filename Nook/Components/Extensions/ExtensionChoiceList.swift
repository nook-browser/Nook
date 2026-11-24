// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionChoiceList.swift
//  Nook
//

import AppKit
import NookDesign
import SwiftUI

/// Which choices are checked, which version is picked where there are two, and what each row
/// has shown of what its extension asks for.
struct ExtensionSelection {
    private(set) var included: Set<String>
    private var picked: [String: String] = [:]
    private var previews: [String: ExtensionConsentPreview] = [:]

    /// Extensions from the browser being imported start checked; apps found on this Mac do not.
    init(_ choices: [ExtensionChoice]) {
        included = Set(choices.filter { !$0.versions[0].isSafari }.map(\.id))
    }

    func shown(for offer: ExtensionOffer) -> ExtensionConsentPreview? {
        previews[offer.id]
    }

    mutating func show(_ preview: ExtensionConsentPreview, for offer: ExtensionOffer) {
        previews[offer.id] = preview
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
        choices.filter { included.contains($0.id) }.map { choice in
            var offer = version(of: choice)
            offer.shown = previews[offer.id]
            return offer
        }
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
    /// What an offer's extension asks for, read from a package on this Mac; nil when there is none.
    let preview: @MainActor (ExtensionOffer) async -> ExtensionConsentPreview?
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
        .task { await loadPreviews() }
    }

    private func loadPreviews() async {
        await withTaskGroup(of: (ExtensionOffer, ExtensionConsentPreview?).self) { group in
            for offer in choices.flatMap(\.versions) {
                group.addTask { @MainActor in (offer, await preview(offer)) }
            }
            for await (offer, lines) in group {
                if let lines { selection.show(lines, for: offer) }
            }
        }
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
                if let lines = selection.shown(for: version) {
                    ExtensionConsentLines(
                        permissions: lines.permissions, hosts: lines.hosts,
                        font: NookDesign.Font.caption, spacing: NookDesign.Spacing.xxs
                    )
                    .onTapGesture(perform: toggle)
                }
            }
        }
    }

    private func subtitle(_ choice: ExtensionChoice, version: ExtensionOffer) -> String {
        let summary = version.source.summary(version: version.version)
        return choice.versions.count > 1 ? "\(summary) · only one version can be installed" : summary
    }
}
