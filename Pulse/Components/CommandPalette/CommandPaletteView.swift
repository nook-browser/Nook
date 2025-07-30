//
//  CommandPaletteView.swift
//  Alto
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

struct CommandPaletteView: View {

    @FocusState private var isSearchFocused: Bool
    @Binding var isSheetOpen: Bool
    @State private var text: String = ""

    var body: some View {
        ZStack {
            Color.black.opacity(0.1)
                .ignoresSafeArea()
                .onTapGesture {
                    isSheetOpen = false
                }
                .gesture(WindowDragGesture())

            VStack {
                VStack(spacing: 0) {

                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 16, weight: .medium))

                        TextField("Search or enter address", text: $text)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .regular))
                            .focused($isSearchFocused)
                            .onKeyPress(.escape) {
                                isSheetOpen = false
                                return .handled
                            }
                            .onKeyPress(.tab) {
                                .handled
                            }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)

                    Spacer()
                }
                .padding(.top, 250)
            }
            .allowsHitTesting(isSheetOpen)
            .opacity(isSheetOpen ? 1.0 : 0.0)
        }
    }
}
