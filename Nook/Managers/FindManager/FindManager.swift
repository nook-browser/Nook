//
//  FindManager.swift
//  Nook
//
//  Created by Assistant on 28/12/2024.
//

import Foundation
import SwiftUI
import WebKit

@MainActor
class FindManager: ObservableObject {
    @Published var isFindBarVisible: Bool = false
    @Published var searchText: String = ""
    @Published var matchCount: Int = 0
    @Published var currentMatchIndex: Int = 0
    @Published var isSearching: Bool = false
    
    var currentTab: Tab?
    
    func showFindBar(for tab: Tab? = nil) {
        currentTab = tab
        isFindBarVisible = true
        searchText = ""
        matchCount = 0
        currentMatchIndex = 0
    }

    func hideFindBar() {
        // Clear highlights from current tab before hiding
        if let tab = currentTab {
            tab.clearFindInPage()
        }

        isFindBarVisible = false
        // Delay clearing text until animation completes (0.25s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.searchText = ""
            self?.matchCount = 0
            self?.currentMatchIndex = 0
            self?.currentTab = nil
        }
    }
    
    func search(for text: String, in tab: Tab?) {
        print("FindManager.search called with text: '\(text)', tab: \(String(describing: tab))")
        
        guard let tab = tab else {
            print("FindManager: No tab provided, clearing search")
            clearSearch()
            return
        }
        
        currentTab = tab
        searchText = text
        isSearching = true
        
        if text.isEmpty {
            print("FindManager: Empty text, clearing search")
            clearSearch()
            return
        }
        
        print("FindManager: Calling tab.findInPage with text: '\(text)'")
        // Use JavaScript-based find functionality
        tab.findInPage(text) { [weak self] result in
            DispatchQueue.main.async {
                self?.isSearching = false
                switch result {
                case .success(let (matchCount, currentIndex)):
                    print("FindManager: Search successful - \(matchCount) matches, current: \(currentIndex)")
                    self?.matchCount = matchCount
                    self?.currentMatchIndex = currentIndex
                case .failure(let error):
                    print("FindManager: Find error: \(error.localizedDescription)")
                    self?.matchCount = 0
                    self?.currentMatchIndex = 0
                }
            }
        }
    }
    
    func findNext() {
        guard let tab = currentTab, !searchText.isEmpty else { return }
        tab.findNextInPage { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (matchCount, currentIndex)):
                    self?.matchCount = matchCount
                    self?.currentMatchIndex = currentIndex
                case .failure(let error):
                    print("Find next error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func findPrevious() {
        guard let tab = currentTab, !searchText.isEmpty else { return }
        tab.findPreviousInPage { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (matchCount, currentIndex)):
                    self?.matchCount = matchCount
                    self?.currentMatchIndex = currentIndex
                case .failure(let error):
                    print("Find previous error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func clearSearch() {
        guard let tab = currentTab else { return }
        tab.clearFindInPage()
        searchText = ""
        matchCount = 0
        currentMatchIndex = 0
    }
    
    func updateCurrentTab(_ tab: Tab?) {
        currentTab = tab
        if isFindBarVisible && !searchText.isEmpty {
            // Re-search in the new tab
            search(for: searchText, in: tab)
        }
    }
}
