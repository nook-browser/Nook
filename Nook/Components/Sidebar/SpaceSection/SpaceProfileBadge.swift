//
//  SpaceProfileBadge.swift
//  Nook
//
//  Small indicator showing a space's assigned profile.
//

import SwiftUI

struct SpaceProfileBadge: View {
    @EnvironmentObject var browserManager: BrowserManager

    let space: Space
    var size: Size = .normal // .compact for tiny dots/icons

    enum Size { case compact, normal }

    private var assignedProfile: Profile? {
        guard let id = space.profileId else { return nil }
        return browserManager.profileManager.profiles.first(where: { $0.id == id })
    }

    private var isCurrentProfile: Bool {
        guard let pid = assignedProfile?.id else { return false }
        return browserManager.currentProfile?.id == pid
    }

    var body: some View {
        Group {
            if let p = assignedProfile {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(isCurrentProfile ? Color.accentColor.opacity(0.15) : Color(.controlBackgroundColor))
                    Image(systemName: p.icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(isCurrentProfile ? .primary : .secondary)
                }
                .frame(width: badgeSide, height: badgeSide)
                .help("Profile: \(p.name)")
                .accessibilityLabel("Profile \(p.name)")
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(.controlBackgroundColor))
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: iconSize, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: badgeSide, height: badgeSide)
                .help("No profile assigned")
                .accessibilityLabel("No profile assigned")
            }
        }
    }

    private var badgeSide: CGFloat { size == .compact ? 14 : 18 }
    private var iconSize: CGFloat { size == .compact ? 9 : 12 }
    private var cornerRadius: CGFloat { size == .compact ? 3 : 4 }
}

