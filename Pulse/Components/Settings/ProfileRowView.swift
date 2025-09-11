//
//  ProfileRowView.swift
//  Pulse
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
        HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.controlBackgroundColor))
                Image(systemName: profile.icon)
                    .font(.system(size: 18, weight: .semibold))
            }
            .frame(width: 32, height: 32)

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(profile.name)
                        .font(.headline)
                        .lineLimit(1)
                    if isCurrent {
                        Label("Current", systemImage: "checkmark.seal.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                HStack(spacing: 8) {
                    Label("\(spacesCount) spaces", systemImage: "rectangle.3.group")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("•").font(.caption).foregroundStyle(.secondary)
                    Label("\(tabsCount) tabs", systemImage: "rectangle.stack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("•").font(.caption).foregroundStyle(.secondary)
                    Label("\(pinnedCount) pinned", systemImage: "pin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("•").font(.caption).foregroundStyle(.secondary)
                    Label(dataSizeDescription, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 6) {
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovering ? Color.primary.opacity(0.04) : Color(.controlBackgroundColor))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Profile row: \(profile.name)")
        .accessibilityHint(isCurrent ? "Current profile" : "Inactive profile")
    }
}
