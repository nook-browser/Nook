//
//  FindManager.swift
//  Nook
//
//  Created by Assistant on 28/12/2024.
//

import Foundation
import SwiftUI
import NookWeb

@MainActor
class FindManager: ObservableObject {
    @Published var isFindBarVisible: Bool = false
    @Published var searchText: String = ""
    @Published var matchCount: Int = 0
    @Published var currentMatchIndex: Int = 0
    @Published var isSearching: Bool = false
    
    var currentSession: PageSession?
    
    func showFindBar(for session: PageSession? = nil) {
        currentSession = session
        isFindBarVisible = true
        searchText = ""
        matchCount = 0
        currentMatchIndex = 0
    }

    func hideFindBar() {
        // Clear highlights from current tab before hiding
        if let session = currentSession {
            session.clearFindInPage()
        }

        isFindBarVisible = false
        // Delay clearing text until animation completes (0.25s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.searchText = ""
            self?.matchCount = 0
            self?.currentMatchIndex = 0
            self?.currentSession = nil
        }
    }
    
    func search(for text: String, in session: PageSession?) {
        guard let session else {
            clearSearch()
            return
        }

        currentSession = session
        searchText = text
        isSearching = true

        if text.isEmpty {
            clearSearch()
            return
        }

        // Use JavaScript-based find functionality
        session.findInPage(text) { [weak self] result in
            DispatchQueue.main.async {
                self?.isSearching = false
                switch result {
                case .success(let (matchCount, currentIndex)):
                    self?.matchCount = matchCount
                    self?.currentMatchIndex = currentIndex
                case .failure:
                    self?.matchCount = 0
                    self?.currentMatchIndex = 0
                }
            }
        }
    }

    func findNext() {
        guard let session = currentSession, !searchText.isEmpty else { return }
        session.findNextInPage { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (matchCount, currentIndex)):
                    self?.matchCount = matchCount
                    self?.currentMatchIndex = currentIndex
                case .failure:
                    break
                }
            }
        }
    }

    func findPrevious() {
        guard let session = currentSession, !searchText.isEmpty else { return }
        session.findPreviousInPage { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (matchCount, currentIndex)):
                    self?.matchCount = matchCount
                    self?.currentMatchIndex = currentIndex
                case .failure:
                    break
                }
            }
        }
    }
    
    func clearSearch() {
        guard let session = currentSession else { return }
        session.clearFindInPage()
        searchText = ""
        matchCount = 0
        currentMatchIndex = 0
    }
    
    func updateCurrentSession(_ session: PageSession?) {
        currentSession = session
        if isFindBarVisible && !searchText.isEmpty {
            // Re-search in the new tab
            search(for: searchText, in: session)
        }
    }
}
