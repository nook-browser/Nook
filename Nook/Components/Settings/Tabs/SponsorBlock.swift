//
//  SponsorBlock.swift
//  Nook
//
//  Created by Claude on 26/03/2026.
//

import SwiftUI

struct SettingsSponsorBlockTab: View {
    @Environment(\.nookSettings) var nookSettings

    var body: some View {
        @Bindable var settings = nookSettings
        Form {
            Section {
                Toggle("SponsorBlock", isOn: $settings.sponsorBlockEnabled)
            } footer: {
                Text("Skip sponsored segments, intros, and other non-content on YouTube using community data from SponsorBlock.")
            }

            if nookSettings.sponsorBlockEnabled {
                Section("Categories") {
                    ForEach(SponsorBlockCategory.allCases) { category in
                        Picker(selection: Binding(
                            get: {
                                SponsorBlockSkipOption(rawValue: nookSettings.sponsorBlockCategoryOptions[category.rawValue] ?? category.defaultSkipOption.rawValue) ?? category.defaultSkipOption
                            },
                            set: { newValue in
                                nookSettings.sponsorBlockCategoryOptions[category.rawValue] = newValue.rawValue
                            }
                        )) {
                            ForEach(SponsorBlockSkipOption.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(sponsorBlockCategoryColor(category))
                                    .frame(width: 8, height: 8)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(category.displayName)
                                    Text(category.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func sponsorBlockCategoryColor(_ category: SponsorBlockCategory) -> Color {
        switch category {
        case .sponsor: return .green
        case .selfpromo: return .yellow
        case .exclusive_access: return Color(red: 0, green: 0.54, blue: 0.36)
        case .interaction: return .purple
        case .intro: return .cyan
        case .outro: return .blue
        case .preview: return .teal
        case .filler: return .indigo
        case .music_offtopic: return .orange
        case .poi_highlight: return .pink
        }
    }
}
