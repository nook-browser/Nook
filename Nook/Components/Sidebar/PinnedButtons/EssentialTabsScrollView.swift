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
    @Environment(BrowserManager.self) private var browserManager
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 0) {
                ForEach(visibleSpaceIndices, id: \.self) { (spaceIndex: Int) in
                    if browserManager.tabManager.spaces.indices.contains(spaceIndex) {
                        let boundaryInfo = getProfileBoundaryInfo(for: spaceIndex)
                        if boundaryInfo.isProfileStart {
                            PinnedGrid(width: width, profileId: boundaryInfo.profileId)
                                .frame(width: width)
                                .id(boundaryInfo.profileId)
                        } else {
                            Color.clear
                                .frame(width: width, height: 44)
                        }
                    } else {
                        EmptyView()
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

        // Safely check previous space profile with bounds checking
        let isProfileStart = spaceIndex == 0 || {
            guard spaceIndex - 1 >= 0 && spaceIndex - 1 < browserManager.tabManager.spaces.count else {
                return true // Treat as profile start if previous space is invalid
            }
            return browserManager.tabManager.spaces[spaceIndex - 1].profileId != currentProfile
        }()

        // Safely check next space profile with bounds checking
        let isProfileEnd = spaceIndex == browserManager.tabManager.spaces.count - 1 || {
            guard spaceIndex + 1 >= 0 && spaceIndex + 1 < browserManager.tabManager.spaces.count else {
                return true // Treat as profile end if next space is invalid
            }
            return browserManager.tabManager.spaces[spaceIndex + 1].profileId != currentProfile
        }()
        
        return (isProfileStart, isProfileEnd, currentProfile)
    }
}
