//
//  URLBarView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

struct URLBarView: View {
    var urlName: String
    
    var body: some View {
        ZStack {
            HStack {
                Text(urlName)
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .foregroundStyle(Color.white.opacity(0.8))
                    
                Spacer()
            }
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
        .background(.white.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
