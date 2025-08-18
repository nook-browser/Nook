//
//  SettingsSection.swift
//  Pulse
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    let description: String?
    let content: Content
    
    init(title: String, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.primary)
            
            if let description = description {
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            
            content
        }
    }
}
