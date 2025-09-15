//
//  CacheDetailsView.swift
//  Nook
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import SwiftUI

struct CacheDetailsView: View {
    let cache: CacheInfo
    let cacheManager: CacheManager
    @Environment(\.dismiss) private var dismiss
    
    private let details: [String: String]
    
    init(cache: CacheInfo, cacheManager: CacheManager) {
        self.cache = cache
        self.cacheManager = cacheManager
        self.details = cacheManager.getCacheDetails(cache)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Basic Info Section
                    sectionView(title: "Basic Information") {
                        detailRow("Domain", cache.displayDomain)
                        detailRow("Total Size", cache.sizeDescription)
                        detailRow("Primary Type", cache.primaryCacheType.rawValue)
                        detailRow("Status", cache.isStale ? "Stale" : "Fresh", 
                                color: cache.isStale ? .orange : .green)
                    }
                    
                    // Storage Breakdown Section
                    sectionView(title: "Storage Breakdown") {
                        detailRow("Disk Usage", cache.diskUsageDescription)
                        detailRow("Memory Usage", cache.memoryUsageDescription)
                        detailRow("Last Modified", cache.lastModifiedDescription)
                        
                        // Storage visualization
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Storage Distribution:")
                                .font(.caption)
                                .fontWeight(.medium)
                            
                            HStack {
                                // Disk usage bar
                                VStack(alignment: .leading) {
                                    Text("Disk")
                                        .font(.caption2)
                                    ProgressView(value: Double(cache.diskUsage), total: Double(cache.size))
                                        .progressViewStyle(.linear)
                                        .tint(.blue)
                                }
                                
                                // Memory usage bar
                                VStack(alignment: .leading) {
                                    Text("Memory")
                                        .font(.caption2)
                                    ProgressView(value: Double(cache.memoryUsage), total: Double(cache.size))
                                        .progressViewStyle(.linear)
                                        .tint(.green)
                                }
                            }
                        }
                    }
                    
                    // Cache Types Section
                    sectionView(title: "Cache Types") {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            ForEach(cache.cacheTypes, id: \.self) { type in
                                HStack {
                                    Image(systemName: type.icon)
                                        .foregroundColor(Color(type.color))
                                    Text(type.rawValue)
                                        .font(.caption)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(4)
                            }
                        }
                    }
                    
                    // Recommendations Section
                    if !cacheManager.getCacheEfficiencyRecommendations().isEmpty {
                        sectionView(title: "Recommendations") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(cacheManager.getCacheEfficiencyRecommendations(), id: \.self) { recommendation in
                                    HStack {
                                        Image(systemName: "lightbulb")
                                            .foregroundColor(.yellow)
                                        Text(recommendation)
                                            .font(.caption)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            
            // Footer
            footerView
        }
        .frame(width: 600, height: 500)
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            HStack {
                Image(systemName: cache.primaryCacheType.icon)
                    .foregroundColor(Color(cache.primaryCacheType.color))
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cache Details")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text(cache.displayDomain)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.escape)
        }
        .padding()
    }
    
    // MARK: - Footer View
    
    private var footerView: some View {
        HStack {
            Button("Copy Details") {
                let detailsText = formatDetailsForClipboard()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(detailsText, forType: .string)
            }
            .buttonStyle(.bordered)
            
            Button("Export Cache Data") {
                let cacheData = cacheManager.exportCacheData()
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(cacheData, forType: .string)
            }
            .buttonStyle(.bordered)
            
            Spacer()
            
            Button("Clear This Cache", role: .destructive) {
                Task {
                    await cacheManager.clearSpecificCache(cache)
                    dismiss()
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    // MARK: - Section View
    
    private func sectionView<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Detail Row
    
    private func detailRow(_ label: String, _ value: String, color: Color? = nil) -> some View {
        HStack {
            Text(label + ":")
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)
            
            Text(value)
                .foregroundColor(color ?? .primary)
                .textSelection(.enabled)
            
            Spacer()
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatDetailsForClipboard() -> String {
        var text = "Cache Details for \(cache.displayDomain)\n"
        text += String(repeating: "=", count: 40) + "\n\n"
        
        for (key, value) in details.sorted(by: { $0.key < $1.key }) {
            text += "\(key): \(value)\n"
        }
        
        text += "\nCache Types:\n"
        for type in cache.cacheTypes {
            text += "- \(type.rawValue)\n"
        }
        
        return text
    }
}

#Preview {
    // Create a sample cache for preview
    let sampleCache = CacheInfo(
        id: UUID(),
        domain: "example.com",
        dataTypes: ["WKWebsiteDataTypeDiskCache", "WKWebsiteDataTypeMemoryCache"],
        size: 1048576, // 1MB
        lastModified: Date().addingTimeInterval(-86400), // 1 day ago
        diskUsage: 786432, // 768KB
        memoryUsage: 262144 // 256KB
    )
    
    CacheDetailsView(cache: sampleCache, cacheManager: CacheManager())
}
