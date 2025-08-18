//
//  SettingsOption.swift
//  Pulse
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import SwiftUI

struct SettingsOption<Content: View>: View {
    let title: String
    let description: String?
    let content: Content
    
    init(title: String, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.content = content()
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                if let description = description {
                    Text(description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            content
        }
    }
}
