//
//  BrowserManager.swift
//  Pulse
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

class BrowserManager: ObservableObject {
    @Published var sidebarWidth: CGFloat = 250
    
    private let userDefaults = UserDefaults.standard
    
    init() {
        loadSidebarWidth()
    }
    
    func updateSidebarWidth(_ width: CGFloat) {
        sidebarWidth = width
        saveSidebarWidth()
    }
    
    private func loadSidebarWidth() {
        let savedWidth = userDefaults.double(forKey: "sidebarWidth")
        if savedWidth > 0 {
            sidebarWidth = savedWidth
        }
    }
    
    private func saveSidebarWidth() {
        userDefaults.set(sidebarWidth, forKey: "sidebarWidth")
    }
}
