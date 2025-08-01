//
//  PinnedGrid.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct PinnedGrid: View {
    let minButtonWidth: CGFloat = 50
    let maxButtonWidth: CGFloat = 150
    @State private var gridHeight: CGFloat = 44  // Default button height

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let spacing: CGFloat = 8

            // Calculate how many columns can fit
            let maxPossibleColumns = Int(
                (availableWidth + spacing) / (minButtonWidth + spacing)
            )
            let actualItemCount = 3  // Your actual number of items
            let columnCount = min(maxPossibleColumns, actualItemCount)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(
                        .flexible(
                            minimum: minButtonWidth,
                            maximum: maxButtonWidth
                        ),
                        spacing: spacing
                    ),
                    count: max(1, columnCount)
                ),
                spacing: 6
            ) {
                PinnedButtonView(iconName: "person", isActive: false)
                PinnedButtonView(iconName: "person", isActive: false)
                PinnedButtonView(iconName: "person", isActive: false)
            }
            .background(
                GeometryReader { gridGeometry in
                    Color.clear
                        .onAppear {
                            gridHeight = gridGeometry.size.height
                        }
                        .onChange(of: columnCount) {
                            DispatchQueue.main.async {
                                gridHeight = gridGeometry.size.height
                            }
                        }
                }
            )
        }
        .frame(height: gridHeight)
    }
}
