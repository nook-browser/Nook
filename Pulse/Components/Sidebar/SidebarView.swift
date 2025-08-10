import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var draggedTabIndex: Int?
    var tabManager = TabManager()
    
    var body: some View {
        if browserManager.isSidebarVisible {
            ZStack {
                // Draggable background layer
                DragWindowView()
                
                // Content layer (sits on top)
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
                    
                    URLBarView()
                        .onTapGesture {
                            print("tapped url bar")
                            browserManager.openCommandPalette()
                            
                        }
                    PinnedGrid()
                    SpaceTittle(
                        spaceName: "Development",
                        spaceIcon: "globe"
                    )
                    if(!browserManager.tabManager.tabs.isEmpty) {
                        SpaceSeparator()
                    }
                    NewTabButton()
                    ForEach(browserManager.tabManager.tabs) { tab in
                        SpaceTab(
                            tabName: tab.name,
                            tabURL: tab.name,
                            tabIcon: tab.favicon,
                            isActive: tab.isCurrentTab,
                            action: {
                                DispatchQueue.main.async {
                                    tab.activate()
                                }
                            },
                            onClose: {
                                DispatchQueue.main.async {
                                    tab.closeTab()
                                }
                            },
                            splitTab: tabManager.currentSplittedTab,
                        )
                        .contextMenu {
                            ContextView(browserManager: _browserManager,tab: tab)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.top, 8)
            }
            .frame(width: browserManager.sidebarWidth)
        }
    }
}

struct ContextView: View {
    @EnvironmentObject var browserManager: BrowserManager
    var tab:Tab
    
    var body: some View {
        // Tab actions
        Button {
            print("New Tab Below")
            browserManager.isCommandPaletteVisible = true
            browserManager.hasSplitView = false
            browserManager.closeSplit()
        } label: {
            HStack {
                Image(systemName: "plus.square.on.square")
                Text("New Tab Below")
            }
        }
        
        Button {
            print("Duplicate Tab")
            // duplicate clicked tab but give it a new ID
            let newtab = Tab(url: tab.url)
            browserManager.tabManager.addTab(newtab)
            print("tab: \(tab)")
            
            
        } label: {
            HStack {
                Image(systemName: "square.on.square")
                Text("Duplicate Tab")
            }
        }
        
        Button {
            print("Split Tab")
            browserManager.hasSplitView = true
            browserManager.tabManager.setSplittedTab()
            browserManager.openSplit()
            
            
        } label: {
            HStack {
                Image(systemName: "rectangle.split.2x1")
                Text("Split Tab")
            }
        }
        
        Divider()
        
        // Audio controls
        Button {
            print("Mute Tab")
        } label: {
            HStack {
                Image(systemName: "speaker.slash")
                Text("Mute Tab")
            }
        }
        
        Divider()
        
        // Moving tabs
        Button {
            print("Move Tab to New Window")
            
        } label: {
            HStack {
                Image(systemName: "arrow.up.right.square")
                Text("Move to New Window")
                
            }
        }
        
        Button {
            print("Move Tab to New Private Window")
        } label: {
            HStack {
                Image(systemName: "eye.slash")
                Text("Move to Private Window")
            }
        }
        
        Divider()
        
        // Content actions
        Button {
            print("Add Tab to Reading List")
        } label: {
            HStack {
                Image(systemName: "book")
                Text("Add to Reading List")
            }
        }
        
        Button {
            print("Bookmark This Tab")
        } label: {
            HStack {
                Image(systemName: "bookmark")
                Text("Bookmark Tab")
            }
        }
        
        Button {
            print("Reload Tab")
            
        } label: {
            HStack {
                Image(systemName: "arrow.clockwise")
                Text("Reload Tab")
            }
        }
        
        Divider()
        
        // Tab management
        Button(role: .destructive) {
            print("Close Tab")
            DispatchQueue.main.async {
                tab.closeTab()
                
            }
        } label: {
            HStack {
                Image(systemName: "xmark")
                Text("Close Tab")
            }
        }
        
        Button(role: .destructive) {
            print("Close Other Tabs")
            print(browserManager.tabManager.tabs)
            for kell in browserManager.tabManager.tabs {
                print("tab: \(tab)")
                print("kek: \(kell)")
                if kell != tab {
                    print("removing tab: \(kell)")
                    browserManager.tabManager.removeTab(kell.id)
                }
            }
        } label: {
            HStack {
                Image(systemName: "xmark.circle")
                Text("Close Other Tabs")
            }
        }
    }
}
