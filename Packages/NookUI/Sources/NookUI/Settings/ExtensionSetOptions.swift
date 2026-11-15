// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionSetOptions.swift
//  NookUI
//
//  The extension choices a profile has: sync with a set another profile uses, or Separate.
//

import SwiftUI
import NookSettings
import NookTabsCore
import NookWeb

public struct ExtensionSetOption: Identifiable, Equatable {
    /// The set to sync with; nil is Separate.
    public let set: UUID?
    public let label: String
    public var id: String { self.set?.uuidString ?? "separate" }
}

@MainActor
public enum ExtensionSetOptions {
    /// One option per set in use by a profile other than `profile`, then Separate. `profile` is
    /// nil for a profile not created yet.
    public static func options(for profile: UUID?, profiles: [ProfileSummary], sets: ExtensionSets,
                               defaultSet: UUID) -> [ExtensionSetOption] {
        let names = Dictionary(profiles.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let synced = sets.choices(profiles: profiles.map(\.id), defaultSet: defaultSet).compactMap { choice in
            let others = choice.members.filter { $0 != profile }
            guard !others.isEmpty else { return nil as ExtensionSetOption? }
            return ExtensionSetOption(set: choice.set, label: "Synced with " + others.compactMap { names[$0] }.joined(separator: ", "))
        }
        return synced + [ExtensionSetOption(set: nil, label: "Separate")]
    }

    /// The option `profile` has now: the set it shares with another profile, else Separate.
    public static func current(for profile: UUID, profiles: [ProfileSummary], sets: ExtensionSets,
                               defaultSet: UUID) -> UUID? {
        let set = sets.setID(forProfile: profile, defaultSet: defaultSet)
        let shared = profiles.contains { $0.id != profile && sets.setID(forProfile: $0.id, defaultSet: defaultSet) == set }
        return shared ? set : nil
    }
}

/// The Extensions picker of a profile row in Settings > Spaces.
struct ExtensionSetPicker: View {
    let profile: UUID
    @Environment(TabsController.self) private var tabs
    @Environment(\.nookSettings) private var settings
    @Environment(\.tabActions) private var actions

    var body: some View {
        if let actions, let defaultSet = actions.defaultExtensionSetID {
            let current = ExtensionSetOptions.current(
                for: profile, profiles: tabs.profiles, sets: settings.extensionSets, defaultSet: defaultSet)
            Picker("Extensions", selection: Binding<UUID?>(
                get: { current },
                set: { if $0 != current { actions.setExtensionSet(ofProfile: profile, to: $0) } }
            )) {
                ForEach(ExtensionSetOptions.options(
                    for: profile, profiles: tabs.profiles, sets: settings.extensionSets, defaultSet: defaultSet)) {
                    Text($0.label).tag($0.set)
                }
            }
        }
    }
}
