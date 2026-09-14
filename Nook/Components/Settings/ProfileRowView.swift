//
//  ProfileRowView.swift
//  Nook
//
//  Row used in Profiles settings list.
//

import SwiftUI

struct ProfileRowView: View {
    let profile: Profile
    let isCurrent: Bool
    let spacesCount: Int
    let tabsCount: Int
    let dataSizeDescription: String
    let pinnedCount: Int
    let onMakeCurrent: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onManageData: () -> Void

    @State private var isHovering: Bool = false

    var body: some View {
        HStack(spacing: NookDesign.Spacing.lg) {
            // Icon
            ZStack {
                NookDesign.Radius.shape(NookDesign.Radius.sm)
                    .fill(NookDesign.Surface.raised)
                Image(systemName: profile.icon)
                    .font(NookDesign.Font.heading)
            }
            .frame(
                width: NookDesign.Size.settingsIcon,
                height: NookDesign.Size.settingsIcon
            )

            // Info
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                HStack(spacing: NookDesign.Spacing.md) {
                    Text(profile.name)
                        .font(NookDesign.Font.label)
                        .lineLimit(1)
                    if isCurrent {
                        Label("Current", systemImage: "checkmark.seal.fill")
                            .labelStyle(.titleAndIcon)
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.green)
                    }
                }
                HStack(spacing: NookDesign.Spacing.md) {
                    Label("\(spacesCount) spaces", systemImage: "rectangle.3.group")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                    Text("•").font(NookDesign.Font.caption).foregroundStyle(.secondary)
                    Label("\(tabsCount) tabs", systemImage: "rectangle.stack")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                    Text("•").font(NookDesign.Font.caption).foregroundStyle(.secondary)
                    Label("\(pinnedCount) pinned", systemImage: "pin")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                    Text("•").font(NookDesign.Font.caption).foregroundStyle(.secondary)
                    Label(dataSizeDescription, systemImage: "internaldrive")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: NookDesign.Spacing.sm) {
                Button(action: onManageData) {
                    Label("Manage Data", systemImage: "wrench.and.screwdriver")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Manage data for this profile")

                Button(action: onRename) {
                    Label("Rename", systemImage: "pencil")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Rename profile")

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Delete profile")

                if !isCurrent {
                    Button(action: onMakeCurrent) {
                        Label("Make Current", systemImage: "checkmark.circle")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(NookDesign.Spacing.md)
        .background(
            NookDesign.Radius.shape(NookDesign.Radius.md)
                .fill(isHovering ? NookDesign.Surface.fill : Color.clear)
        )
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) { isHovering = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Profile row: \(profile.name)")
        .accessibilityHint(isCurrent ? "Current profile" : "Inactive profile")
    }
}
