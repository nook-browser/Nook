// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  YouTube.swift
//  Nook
//
//  Created by Claude on 26/03/2026.
//

import NookSettings
import SwiftUI
import NookDesign
import NookTweaks

public struct SettingsYouTubeTab: View {
    @Environment(NookSettingsService.self) var nookSettings

    public init() {}

    public var body: some View {
        @Bindable var settings = nookSettings
        Form {
            Section {
                Picker("Videos per row", selection: $settings.youTubeVideosPerRow) {
                    Text("Automatic").tag(0)
                    ForEach(YouTubeTweaks.videosPerRowRange, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }
                Toggle("Frame thumbnails", isOn: $settings.youTubeFrameThumbnails)
                Toggle("Disable hover previews", isOn: $settings.youTubeNoHoverPreview)
            } header: {
                Text("Layout")
            } footer: {
                Text("Videos per row applies to Home, Subscriptions, and channel pages. Frame thumbnails show a still from the video instead of the uploader's thumbnail.")
            }

            Section("Hide") {
                Toggle("Shorts", isOn: $settings.youTubeHideShorts)
                ForEach(YouTubeHomeSection.allCases) { section in
                    Toggle("Home: \(section.displayName)", isOn: Binding(
                        get: { nookSettings.youTubeHiddenHomeSections.contains(section.rawValue) },
                        set: { hidden in
                            nookSettings.youTubeHiddenHomeSections.removeAll { $0 == section.rawValue }
                            if hidden { nookSettings.youTubeHiddenHomeSections.append(section.rawValue) }
                        }
                    ))
                }
            }

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
                            Label {
                                VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                                    Text(category.displayName)
                                    Text(category.description)
                                        .font(NookDesign.Font.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Circle()
                                    .fill(sponsorBlockCategoryColor(category))
                                    .frame(
                                        width: NookDesign.Size.statusDot,
                                        height: NookDesign.Size.statusDot
                                    )
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
