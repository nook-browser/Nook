//
//  SpaceProfileBadge.swift
//  Nook
//
//  Small indicator showing a space's assigned profile.
//

import NookTabsCore
import SwiftUI

struct SpaceProfileBadge: View {
    @EnvironmentObject var browserManager: BrowserManager

    let space: SpaceRecord
    var size: Size = .normal // .compact for tiny dots/icons

    enum Size { case compact, normal }

    private var assignedProfile: Profile? {
        browserManager.profileManager.profiles.first(where: { $0.id == space.profileID })
    }

    private var isCurrentProfile: Bool {
        guard let pid = assignedProfile?.id else { return false }
        return browserManager.currentProfile?.id == pid
    }

    var body: some View {
        Group {
            if let p = assignedProfile {
                ZStack {
                    NookDesign.Radius.shape(cornerRadius)
                        .fill(isCurrentProfile ? Color.accentColor.opacity(0.15) : Color(.controlBackgroundColor))
                    Image(systemName: p.icon)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(isCurrentProfile ? .primary : .secondary)
                }
                .frame(width: badgeSide, height: badgeSide)
                .help("Profile: \(p.name)")
                .accessibilityLabel("Profile \(p.name)")
            } else {
                // This should never happen now since we always show the default profile
                ZStack {
                    NookDesign.Radius.shape(cornerRadius)
                        .fill(Color(.controlBackgroundColor))
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: iconSize, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: badgeSide, height: badgeSide)
                .help("Default profile")
                .accessibilityLabel("Default profile")
            }
        }
    }

    private var badgeSide: CGFloat { size == .compact ? 14 : 18 }
    private var iconSize: CGFloat { size == .compact ? 9 : 12 }
    private var cornerRadius: CGFloat { NookDesign.Radius.xs }
}

