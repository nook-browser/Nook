//
//  EssentialTabsScrollView.swift
//  Nook
//
//  Created by Jonathan Caudill on 04/09/2025.
//

import SwiftUI

struct EssentialTabsScrollView: View {
    let width: CGFloat
    let currentSpaceScrollID: Binding<UUID?>
    let visibleSpaceIndices: [Int]
    @EnvironmentObject var browserManager: BrowserManager
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(visibleSpaceIndices, id: \.self) { spaceIndex in
                    let space = browserManager.tabManager.spaces[spaceIndex]
                    let boundaryInfo = getProfileBoundaryInfo(for: spaceIndex)
                    
                    if boundaryInfo.isProfileStart {
                        // Show essential tabs at profile start
                        PinnedGrid(width: width, profileId: boundaryInfo.profileId)
                            .frame(width: width)
                            .id(boundaryInfo.profileId)
                    } else {
                        // Empty space to maintain alignment with spaces ScrollView
                        Color.clear
                            .frame(width: width, height: 44)
                    }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: currentSpaceScrollID, anchor: .topLeading)
        .scrollIndicators(.hidden)
        .scrollDisabled(true) // Controlled by spaces ScrollView
    }
    
    private func getProfileBoundaryInfo(for spaceIndex: Int) -> (isProfileStart: Bool, isProfileEnd: Bool, profileId: UUID?) {
        guard spaceIndex >= 0 && spaceIndex < browserManager.tabManager.spaces.count else {
            return (false, false, nil)
        }
        
        let currentSpace = browserManager.tabManager.spaces[spaceIndex]
        let currentProfile = currentSpace.profileId
        
        let isProfileStart = spaceIndex == 0 || 
                            browserManager.tabManager.spaces[spaceIndex - 1].profileId != currentProfile
        
        let isProfileEnd = spaceIndex == browserManager.tabManager.spaces.count - 1 || 
                          browserManager.tabManager.spaces[spaceIndex + 1].profileId != currentProfile
        
        return (isProfileStart, isProfileEnd, currentProfile)
    }
}
