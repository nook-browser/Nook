//
//  ImportManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 29/09/2025.
//

import Foundation
import Combine
import SwiftUI

class ImportManager: ObservableObject {
    
    func importArcSidebarData() async -> ArcImportResult {
        
        let fileURL = getArcSidebarFileURL()
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return ArcImportResult(topTabs: [], spaces: [])
        }
        
        do {
            let result = try parseArcSidebarData(from: fileURL)
            return result
        } catch {
            return ArcImportResult(topTabs: [], spaces: [])
        }
    }
    
    func importDiaData() async -> DiaImportResult {
        let fileURL = getDiaFileURL()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return DiaImportResult(favoriteTabs: [], windowTabs: [])
        }

        do {
            let result = try parseDiaData(from: fileURL)
            return result
        } catch {
            return DiaImportResult(favoriteTabs: [], windowTabs: [])
        }
    }

    func checkSafariExport(at directoryURL: URL) -> SafariExportContents? {
        return validateSafariExport(at: directoryURL)
    }

    func importSafariData(from directoryURL: URL, importBookmarks: Bool, importHistory: Bool) async -> SafariImportResult {
        do {
            let result = try parseSafariExport(from: directoryURL, importBookmarks: importBookmarks, importHistory: importHistory)
            return result
        } catch {
            return SafariImportResult(bookmarks: [], history: [])
        }
    }

    private func getArcSidebarFileURL() -> URL {
        let url = URL(fileURLWithPath: NSString(string: "~/Library/Application Support/Arc/StorableSidebar.json")
            .expandingTildeInPath
        )

        return url
    }

    private func getDiaFileURL() -> URL {
        URL(fileURLWithPath: NSString(string: "~/Library/Application Support/Dia/StorableProfileContainers.json")
            .expandingTildeInPath
        )
    }
}
