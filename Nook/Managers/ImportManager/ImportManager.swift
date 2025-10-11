//
//  ImportManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 29/09/2025.
//

import Foundation
import Combine
import SwiftUI

class ImportManager {
    
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
    
    private func getArcSidebarFileURL() -> URL {
        let url = URL(fileURLWithPath: NSString(string: "~/Library/Application Support/Arc/StorableSidebar.json")
            .expandingTildeInPath
        )
        
        return url
    }
}
