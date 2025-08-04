//
//  SpacesList.swift
//  Pulse
//
//  Created by Maciek Bagiński on 04/08/2025.
//
import SwiftUI

struct SpacesList: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var isHovering: Bool = false

    private var currentSpaceID: UUID? {
        browserManager.tabManager.currentSpace?.id
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(browserManager.tabManager.spaces, id: \.id) { space in
                SpacesListItem(space: space)
                    .id(space.id)
            }
        }
    }
}
