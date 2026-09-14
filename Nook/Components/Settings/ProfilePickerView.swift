//
//  ProfilePickerView.swift
//  Nook
//
//  Reusable picker for selecting a profile in menus and settings.
//

import SwiftUI

struct ProfilePickerView: View {
    @EnvironmentObject var browserManager: BrowserManager

    // Binding to the selected profile id (must always have a profile)
    @Binding var selectedProfileId: UUID

    // Optional callback when a selection is made
    var onSelect: ((UUID) -> Void)? = nil

    // Visual style variants
    var compact: Bool = true

    var body: some View {
        let profiles = browserManager.profileManager.profiles

        if profiles.isEmpty {
            EmptyProfilesView()
        } else if compact {
            CompactListView(
                profiles: profiles,
                selectedProfileId: $selectedProfileId,
                onSelect: onSelect
            )
        } else {
            FullListView(
                profiles: profiles,
                selectedProfileId: $selectedProfileId,
                onSelect: onSelect
            )
        }
    }

    // MARK: - Subviews
    @ViewBuilder
    private func row(for profile: Profile) -> some View {
        HStack(spacing: NookDesign.Spacing.md) {
            Image(systemName: profile.icon)
                .font(NookDesign.Font.label)
            Text(profile.name)
                .lineLimit(1)
            Spacer()
            if selectedProfileId == profile.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel("Profile: \(profile.name)")
        .accessibilityHint(selectedProfileId == profile.id ? "Selected" : "Not selected")
        .onTapGesture {
            select(profile.id)
        }
    }

    private func select(_ id: UUID) {
        selectedProfileId = id
        onSelect?(id)
    }

    // Compact vertical list – suitable for menus/context menus
    private struct CompactListView: View {
        let profiles: [Profile]
        @Binding var selectedProfileId: UUID
        var onSelect: ((UUID) -> Void)?

        var body: some View {
            VStack(alignment: .leading, spacing: NookDesign.Spacing.sm) {
                ForEach(profiles, id: \.id) { p in
                    Button(action: { select(p.id) }) {
                        HStack(spacing: NookDesign.Spacing.md) {
                            Image(systemName: p.icon).font(NookDesign.Font.body)
                            Text(p.name).font(NookDesign.Font.body)
                            Spacer()
                            if selectedProfileId == p.id { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        private func select(_ id: UUID) {
            selectedProfileId = id
            onSelect?(id)
        }
    }

    // Full list with dividers and clearer spacing – for settings
    private struct FullListView: View {
        let profiles: [Profile]
        @Binding var selectedProfileId: UUID
        var onSelect: ((UUID) -> Void)?

        var body: some View {
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xs) {
                ForEach(profiles, id: \.id) { p in
                    Button(action: { select(p.id) }) {
                        HStack(spacing: NookDesign.Spacing.sectionGap) {
                            ZStack {
                                NookDesign.Radius.shape(NookDesign.Radius.sm)
                                    .fill(NookDesign.Surface.raised)
                                Image(systemName: p.icon).font(NookDesign.Font.title)
                            }
                            .frame(
                                width: NookDesign.Size.settingsChip,
                                height: NookDesign.Size.settingsChip
                            )
                            Text(p.name).lineLimit(1)
                            Spacer()
                            if selectedProfileId == p.id { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, NookDesign.Spacing.xxs)
                }
            }
        }

        private func select(_ id: UUID) {
            selectedProfileId = id
            onSelect?(id)
        }
    }

    private struct EmptyProfilesView: View {
        var body: some View {
            HStack(spacing: NookDesign.Spacing.md) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
                Text("No profiles available")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, NookDesign.Spacing.xs)
            .accessibilityLabel("No profiles available")
        }
    }
}
