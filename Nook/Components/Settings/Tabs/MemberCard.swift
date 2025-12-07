//
//  MemberCard.swift
//  Nook
//
//  Created by Maciek Bagiński on 07/12/2025.
//

import ColorfulX
import SwiftUI

struct MemberCard: View {
    @Environment(\.openURL) var openURL


    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Nook Member")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
            Text("Free from The Browser Company")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
            Spacer()
            Text("Thank you")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .italic()
            Text("For supporting our project")
                .font(.system(size: 13, weight: .medium))
            Spacer()

            HStack {
                SocialButon(icon: "github.fill", label: "Source code", action: {
                    openURL(URL(string: "https://github.com/nook-browser/Nook")!)
                })
                SocialButon(icon: "opencollective-fill", label: "Support us", action: {
                    openURL(URL(string: "https://opencollective.com/nook-browser")!)

                })
            }


        }
        .padding(.vertical, 32)
        .frame(width: 250, height: 400)
        .background(
            ColorfulView(
                color: .aurora,
                speed: .constant(0.5),
                noise: .constant(4)
            )
        )
        .clipShape(
            RoundedRectangle(cornerRadius: 14)
        )
    }
}

struct SocialButon: View {
    @State private var isHovered: Bool = false
    var icon: String
    var label: String
    var action: () -> Void
    
    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 4) {
                Image(icon)
                    .font(.system(size: 16, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(isHovered ? .white : .white.opacity(0.6))
        }
        .buttonStyle(.plain)
        .onHover { state in
            isHovered = state
        }
    }
}
