import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var selectedSpaceID: UUID?
    @State private var spaceName = ""

    var body: some View {
        if browserManager.isSidebarVisible {
            ZStack {
                VStack(spacing: 8) {
                    HStack(spacing: 2) {
                        NavButtonsView()
                    }
                    .frame(height: 30)
                    .background(
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                DispatchQueue.main.async {
                                    zoomCurrentWindow()
                                }
                            }
                    )
                    .backgroundDraggable()

                    URLBarView()
                    PinnedGrid()
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 0) {
                                ForEach(
                                    browserManager.tabManager.spaces,
                                    id: \.id
                                ) { space in
                                    SpaceView(
                                        space: space,
                                        tabs: tabManagerTabs(in: space),
                                        isActive: browserManager.tabManager
                                            .currentSpace?.id == space.id,
                                        width: browserManager.sidebarWidth,
                                        onSetActive: {
                                            browserManager.tabManager
                                                .setActiveSpace(space)
                                            selectedSpaceID = space.id
                                            withAnimation(
                                                .easeInOut(duration: 0.25)
                                            ) {
                                                proxy.scrollTo(
                                                    space.id,
                                                    anchor: .center
                                                )
                                            }
                                        },
                                        onActivateTab: {
                                            browserManager.tabManager
                                                .setActiveTab(
                                                    $0
                                                )
                                        },
                                        onCloseTab: {
                                            browserManager.tabManager.removeTab(
                                                $0.id
                                            )
                                        },
                                        onPinTab: {
                                            browserManager.tabManager.pinTab($0)
                                        },
                                        onMoveTabUp: {
                                            browserManager.tabManager.moveTabUp($0.id)
                                        },
                                        onMoveTabDown: {
                                            browserManager.tabManager.moveTabDown($0.id)
                                        }
                                    )
                                    .id(space.id)
                                    .frame(width: browserManager.sidebarWidth)
                                    .scrollTargetLayout()
                                }
                            }
                        }
                        .frame(width: browserManager.sidebarWidth)
                        .contentMargins(.horizontal, 0)
                        .scrollTargetBehavior(.viewAligned)
                        .onChange(
                            of: browserManager.tabManager.currentSpace?.id
                        ) {
                            _,
                            newID in
                            guard let newID else { return }
                            selectedSpaceID = newID
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(newID, anchor: .center)
                            }
                        }
                        .onAppear {
                            selectedSpaceID =
                                browserManager.tabManager.currentSpace?.id
                            if let id = selectedSpaceID {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                    //MARK: - Bottom
                    HStack {
                        NavButton(iconName: "square.and.arrow.down") {
                            print("Downloads button pressed")
                        }
                        Spacer()
                        SpacesList()
                        Spacer()
                        NavButton(iconName: "plus") {
                            showSpaceCreationDialog()
                        }

                    }

                }
                .padding(.top, 8)
                .frame(width: browserManager.sidebarWidth)
            }

            .frame(width: browserManager.sidebarWidth)
        }
    }
    private func tabManagerTabs(in space: Space) -> [Tab] {
        browserManager.tabManager.tabs(in: space)
    }

    func scrollToSpace(_ space: Space, proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(space.id, anchor: .center)
        }
    }
    
    private func showSpaceCreationDialog() {
        let dialog = SpaceCreationDialog(
            spaceName: $spaceName,
            onSave: {
                // Create the space with the name from dialog
                browserManager.tabManager.createSpace(
                    name: spaceName.isEmpty ? "New Space" : spaceName,
                    icon: "sparkles"
                )
                browserManager.dialogManager.closeDialog()
                
                // Reset form
                spaceName = ""
            },
            onCancel: {
                browserManager.dialogManager.closeDialog()
                
                // Reset form
                spaceName = ""
            }
        )
        
        browserManager.dialogManager.showDialog(dialog)
    }
}
