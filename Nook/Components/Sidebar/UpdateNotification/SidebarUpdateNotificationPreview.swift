//
//  SidebarUpdateNotificationPreview.swift
//  Nook
//
//  Created by Jonathan Caudill on 27/09/2025.
//

import SwiftUI

#Preview {
    VStack(spacing: 16) {
        Text("Expanded State")
            .font(.caption)
            .foregroundColor(.secondary)

        // Expanded notification view
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.dotted")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.blue.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text("A new version of Nook is available!")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)

                Text("Click to restart and update")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: {}) {
                Text("Restart and Update")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.2))
                    )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.blue.opacity(0.6))
        )
        .frame(width: 300)

        Text("Collapsed State")
            .font(.caption)
            .foregroundColor(.secondary)

        // Collapsed notification view
        Button(action: {}) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.dotted")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text("Restart and Update")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.blue.opacity(0.6))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: 300)
    }
    .padding()
    .frame(width: 400, height: 300)
    .background(Color.gray.opacity(0.1))
}
