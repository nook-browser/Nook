//
//  FindBarView.swift
//  Nook
//
//  Created by Assistant on 28/12/2024.
//

import SwiftUI

struct FindBarView: View {
    @ObservedObject var findManager: FindManager
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Search text field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                
                TextField("Find in page", text: $findManager.searchText)
                    .textFieldStyle(.plain)
                    .focused($isTextFieldFocused)
                    .font(.system(size: 13))
                    .onSubmit {
                        findManager.findNext()
                    }
                    .onChange(of: findManager.searchText) { _, newValue in
                        findManager.search(for: newValue, in: findManager.currentTab)
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .frame(minWidth: 200)
            
            // Match count
            if findManager.matchCount > 0 {
                Text("\(findManager.currentMatchIndex) of \(findManager.matchCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 50)
            } else if !findManager.searchText.isEmpty {
                Text("No matches")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 50)
            }
            
            // Navigation buttons
            HStack(spacing: 2) {
                Button(action: {
                    findManager.findPrevious()
                }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(findManager.searchText.isEmpty)
                .frame(width: 24, height: 24)
                
                Button(action: {
                    findManager.findNext()
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(findManager.searchText.isEmpty)
                .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            
            // Close button
            Button(action: {
                findManager.hideFindBar()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 24)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 2)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFieldFocused = true
            }
        }
        .onKeyPress(.escape) {
            findManager.hideFindBar()
            return .handled
        }
    }
}

#Preview {
    FindBarView(findManager: FindManager())
        .frame(width: 400, height: 40)
}
