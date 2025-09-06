//
//  ProfilePickerView.swift
//  Pulse
//
//  Reusable picker for selecting a profile in menus and settings.
//

import SwiftUI

struct ProfilePickerView: View {
    @EnvironmentObject var browserManager: BrowserManager

    // Binding to the selected profile id (nil = unassigned/default)
    @Binding var selectedProfileId: UUID?

    // Optional callback when a selection is made
    var onSelect: ((UUID?) -> Void)? = nil

    // Visual style variants
    var compact: Bool = true
    var showNoneOption: Bool = true

    var body: some View {
        let profiles = browserManager.profileManager.profiles

        if profiles.isEmpty {
            EmptyProfilesView()
        } else if compact {
            CompactListView(
                profiles: profiles,
                showNoneOption: showNoneOption,
                selectedProfileId: $selectedProfileId,
                onSelect: onSelect
            )
        } else {
            FullListView(
                profiles: profiles,
                showNoneOption: showNoneOption,
                selectedProfileId: $selectedProfileId,
                onSelect: onSelect
            )
        }
    }

    // MARK: - Subviews
    @ViewBuilder
    private func row(for profile: Profile) -> some View {
        HStack(spacing: 8) {
            Image(systemName: profile.icon)
                .font(.system(size: 14, weight: .semibold))
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

    @ViewBuilder
    private func noneRow() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 14, weight: .semibold))
            Text("No Profile")
            Spacer()
            if selectedProfileId == nil {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel("No Profile")
        .accessibilityHint(selectedProfileId == nil ? "Selected" : "Not selected")
        .onTapGesture {
            select(nil)
        }
    }

    private func select(_ id: UUID?) {
        selectedProfileId = id
        onSelect?(id)
    }

    // Compact vertical list – suitable for menus/context menus
    private struct CompactListView: View {
        let profiles: [Profile]
        let showNoneOption: Bool
        @Binding var selectedProfileId: UUID?
        var onSelect: ((UUID?) -> Void)?

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                if showNoneOption {
                    Button(action: { select(nil) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .font(.system(size: 13))
                            Text("No Profile")
                                .font(.system(size: 13))
                            Spacer()
                            if selectedProfileId == nil { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                        }
                    }
                    .buttonStyle(.plain)
                }
                ForEach(profiles, id: \.id) { p in
                    Button(action: { select(p.id) }) {
                        HStack(spacing: 8) {
                            Image(systemName: p.icon).font(.system(size: 13))
                            Text(p.name).font(.system(size: 13))
                            Spacer()
                            if selectedProfileId == p.id { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        private func select(_ id: UUID?) {
            selectedProfileId = id
            onSelect?(id)
        }
    }

    // Full list with dividers and clearer spacing – for settings
    private struct FullListView: View {
        let profiles: [Profile]
        let showNoneOption: Bool
        @Binding var selectedProfileId: UUID?
        var onSelect: ((UUID?) -> Void)?

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                if showNoneOption {
                    Button(action: { select(nil) }) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(.controlBackgroundColor))
                                Image(systemName: "person.crop.circle.badge.questionmark")
                                    .font(.system(size: 16))
                            }
                            .frame(width: 24, height: 24)
                            Text("No Profile").lineLimit(1)
                            Spacer()
                            if selectedProfileId == nil { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
                ForEach(profiles, id: \.id) { p in
                    Button(action: { select(p.id) }) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(.controlBackgroundColor))
                                Image(systemName: p.icon).font(.system(size: 16))
                            }
                            .frame(width: 24, height: 24)
                            Text(p.name).lineLimit(1)
                            Spacer()
                            if selectedProfileId == p.id { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            }
        }

        private func select(_ id: UUID?) {
            selectedProfileId = id
            onSelect?(id)
        }
    }

    private struct EmptyProfilesView: View {
        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
                Text("No profiles available")
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .accessibilityLabel("No profiles available")
        }
    }
}
