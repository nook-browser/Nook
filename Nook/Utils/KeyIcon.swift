//
//  KeyIcon.swift
//  Nook
//
//  Created by Maciek Bagiński on 21/09/2025.
//
import SwiftUI

enum KeyIconType {
    case symbol
    case letter
}

struct KeyIcon: View {
    var iconName: String
    var type: KeyIconType

    var body: some View {
        ZStack {
            if type == .letter {
                Text(iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: "605E7A"))
                    .padding(4)
                    .frame(width: 18, height: 18)
                    .background(Color(hex: "DDDDE5"))
                    .clipShape(
                        RoundedRectangle(cornerRadius: 4)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(hex: "9B9AA7"), lineWidth: 1)
                    }
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: "605E7A"))
                    .padding(4)
                    .frame(width: 18, height: 18)
                    .background(Color(hex: "DDDDE5"))
                    .clipShape(
                        RoundedRectangle(cornerRadius: 4)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(hex: "9B9AA7"), lineWidth: 1)
                    }
            }
        }
    }
}

#Preview {
    HStack {
        KeyIcon(iconName: "command", type: .symbol)
        KeyIcon(iconName: "C", type: .letter)
    }
    .frame(width: 100, height: 100)
}
