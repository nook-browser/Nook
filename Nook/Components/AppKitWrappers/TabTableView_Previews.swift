import SwiftUI
import AppKit

/// Mock data source for testing TabTableView
@MainActor
class MockTabListDataSource: TabListDataSource, ObservableObject {
    @Published var tabs: [Tab]
    
    init() {
        // Create mock tabs with different states
        self.tabs = [
            Tab(url: URL(string: "https://www.apple.com")!, name: "Apple"),
            Tab(url: URL(string: "https://www.google.com")!, name: "Google"),
            Tab(url: URL(string: "https://www.github.com")!, name: "GitHub"),
            Tab(url: URL(string: "https://www.stackoverflow.com")!, name: "Stack Overflow")
        ]
        
        // Set some tabs as loaded with audio
        tabs[1].loadingState = .didFinish
        tabs[1].hasAudioContent = true
        tabs[2].loadingState = .didFinish
    }
    
    func moveTab(from sourceIndex: Int, to targetIndex: Int) {
        guard sourceIndex < tabs.count && targetIndex <= tabs.count else { return }
        
        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: targetIndex)
        
        print("Moved tab from \(sourceIndex) to \(targetIndex)")
    }
    
    func selectTab(at index: Int) {
        guard index < tabs.count else { return }
        print("Selected tab: \(tabs[index].name)")
    }
    
    func closeTab(at index: Int) {
        guard index < tabs.count else { return }
        tabs.remove(at: index)
        print("Closed tab at index \(index)")
    }
    
    func toggleMuteTab(at index: Int) {
        guard index < tabs.count else { return }
        print("Toggled mute for tab: \(tabs[index].name)")
    }
    
    func contextMenuForTab(at index: Int) -> NSMenu? {
        guard index < tabs.count else { return nil }
        
        let menu = NSMenu()
        let tab = tabs[index]
        
        let reloadItem = NSMenuItem(title: "Reload \(tab.name)", action: nil, keyEquivalent: "")
        menu.addItem(reloadItem)
        
        let closeItem = NSMenuItem(title: "Close \(tab.name)", action: nil, keyEquivalent: "")
        menu.addItem(closeItem)
        
        return menu
    }
}

/// Preview for TabTableView
struct TabTableView_Previews: PreviewProvider {
    static var previews: some View {
        let browserManager = BrowserManager()
        return VStack {
            Text("TabTableView Preview")
                .font(.headline)
                .padding()
            
            TabTableView(dataSource: MockTabListDataSource())
                .frame(width: 250, height: 300)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding()
        }
        .frame(width: 300, height: 400)
        .background(Color(NSColor.windowBackgroundColor))
        .environmentObject(browserManager)
    }
}

#Preview {
    TabTableView_Previews.previews
}
