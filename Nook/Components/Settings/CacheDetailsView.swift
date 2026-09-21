// Licensed under GPL-3.0. See LICENSE.
//
//  CacheDetailsView.swift
//  Nook
//
//  Created by Jonathan Caudill on 15/08/2025.
//

import SwiftUI
import NookDesign

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
            Form {
                Section("Cache Details") {
                    LabeledContent("Domain") {
                        Text(cache.displayDomain)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Total Size") {
                        Text(cache.sizeDescription)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Primary Type") {
                        Text(cache.primaryCacheType.rawValue)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Status") {
                        Text(cache.isStale ? "Stale" : "Fresh")
                            .foregroundStyle(cache.isStale ? .orange : .green)
                            .textSelection(.enabled)
                    }
                }

                Section("Storage Breakdown") {
                    LabeledContent("Disk Usage") {
                        Text(cache.diskUsageDescription)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Memory Usage") {
                        Text(cache.memoryUsageDescription)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Last Modified") {
                        Text(cache.lastModifiedDescription)
                            .textSelection(.enabled)
                    }

                    LabeledContent("Disk") {
                        ProgressView(value: Double(cache.diskUsage), total: Double(cache.size))
                            .progressViewStyle(.linear)
                            .tint(.blue)
                    }
                    LabeledContent("Memory") {
                        ProgressView(value: Double(cache.memoryUsage), total: Double(cache.size))
                            .progressViewStyle(.linear)
                            .tint(.green)
                    }
                }

                Section("Cache Types") {
                    ForEach(cache.cacheTypes, id: \.self) { type in
                        Label {
                            Text(type.rawValue)
                        } icon: {
                            Image(systemName: type.icon)
                                .foregroundStyle(Color(type.color))
                        }
                    }
                }

                if !cacheManager.getCacheEfficiencyRecommendations().isEmpty {
                    Section("Recommendations") {
                        ForEach(cacheManager.getCacheEfficiencyRecommendations(), id: \.self) { recommendation in
                            Label {
                                Text(recommendation)
                            } icon: {
                                Image(systemName: "lightbulb")
                                    .foregroundStyle(.yellow)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            footerView
        }
        .frame(
            width: NookDesign.Size.sheetMediumWidth,
            height: NookDesign.Size.sheetMediumHeight
        )
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

            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.escape)
        }
        .padding(NookDesign.Spacing.xl)
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
