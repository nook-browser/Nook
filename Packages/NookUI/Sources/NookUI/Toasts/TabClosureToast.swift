// Licensed under GPL-3.0. See LICENSE.
//
//  TabClosureToast.swift
//  Nook
//
//  Created by Jonathan Caudill on 02/10/2025.
//

import SwiftUI
import NookDesign

public struct TabClosureToast: View {
    @Environment(\.tabActions) private var actions

    private var count: Int { actions?.tabClosureToastCount ?? 0 }

    public init() {}

    public var body: some View {
        ToastView {
            HStack(spacing: 8) {
                Image(systemName: "arrow.counterclockwise")
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.primary)
                    .frame(width: 14, height: 14)
                    .padding(4)
                    .background(NookDesign.Surface.fill)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
                    .overlay {
                        NookDesign.Radius.shape(NookDesign.Radius.sm)
                            .stroke(NookDesign.Surface.hairline, lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count) tab\(count > 1 ? "s" : "") closed")
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.primary)

                    Text("Press ⌘Z to undo")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .transition(.toast)
        .onAppear {
            // Auto-dismiss after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                actions?.hideTabClosureToast()
            }
        }
        .onTapGesture {
            actions?.hideTabClosureToast()
        }
    }
}
