//
//  SettingsView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var selectedTab: SettingsTab = .general
    
    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case theme = "Theme"
        case profiles = "Profiles"
        case advanced = "Advanced"
        
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .theme: return "paintbrush"
            case .profiles: return "person.crop.circle"
            case .advanced: return "gearshape.2"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button(action: {
                        selectedTab = tab
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14, weight: .medium))
                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(selectedTab == tab ? .primary : .secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    if tab != SettingsTab.allCases.last {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
            
            Divider()
                .padding(.horizontal, 20)
            Group {
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .theme:
                    ThemeSettingsView()
                case .profiles:
                    ProfilesSettingsView()
                case .advanced:
                    AdvancedSettingsView()
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
        }
        .frame(width: 600, height: 500)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
