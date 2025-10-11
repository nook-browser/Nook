//
//  SpaceProfileDropdown.swift
//  Nook
//
//  Single dropdown for space profile assignment showing current profile.
//

import SwiftUI

struct SpaceProfileDropdown: View {
    @Environment(BrowserManager.self) private var browserManager

    let currentProfileId: UUID
    let onProfileSelected: (UUID) -> Void

    var body: some View {
        let profiles = browserManager.profileManager.profiles

        Menu {
            ForEach(profiles, id: \.id) { profile in
                Button(action: { onProfileSelected(profile.id) }) {
                    HStack(spacing: 8) {
                        Image(systemName: profile.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(profile.name)
                            .font(.system(size: 13))
                        Spacer()
                        if profile.id == currentProfileId {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        } label: {
            HStack(spacing: 6) {
                if let currentProfile = profiles.first(where: { $0.id == currentProfileId }) {
                    Image(systemName: currentProfile.icon)
                        .font(.system(size: 13, weight: .semibold))
                    Text(currentProfile.name)
                        .font(.system(size: 13))
                } else {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 13))
                    Text("Default Profile")
                        .font(.system(size: 13))
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
