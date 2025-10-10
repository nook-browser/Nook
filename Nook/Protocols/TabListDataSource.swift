import Foundation
import SwiftUI

/// Protocol to bridge between AppKit table view and Tab management system
@MainActor
protocol TabListDataSource {
    /// The current list of tabs to display
    var tabs: [Tab] { get }
    
    /// Handle tab reordering
    /// - Parameters:
    ///   - sourceIndex: The original index of the tab
    ///   - targetIndex: The new index where the tab should be moved
    func moveTab(from sourceIndex: Int, to targetIndex: Int)
    
    /// Handle tab selection
    /// - Parameter index: The index of the tab to select
    func selectTab(at index: Int)
    
    /// Close a tab
    /// - Parameter index: The index of the tab to close
    func closeTab(at index: Int)
    
    /// Toggle mute state of a tab
    /// - Parameter index: The index of the tab to toggle mute
    func toggleMuteTab(at index: Int)
    
    /// Provide context menu for a tab
    /// - Parameter index: The index of the tab
    /// - Returns: An NSMenu for the tab, or nil if no menu should be shown
    func contextMenuForTab(at index: Int) -> NSMenu?
}
