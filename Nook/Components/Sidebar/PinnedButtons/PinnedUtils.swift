//
//  PinnedUtils.swift
//  Nook
//
//  Created by Maciek Bagiński on 07/12/2025.
//

import SwiftUI



// Enum for customizing pinned tabs look
enum PinnedTabsConfiguration: String, CaseIterable, Identifiable {
    case large = "large"
    case small = "small"
    
    var id: String { rawValue }
    
    var faviconHeight: CGFloat {
        switch self {
        case .large:
            return 16
        case .small:
            return 16
        }
    }
    
    var name: String {
        switch self {
        case .large:
            return "Arc"
        case .small:
            return "Dia"
        }
    }
    
    var minWidth: CGFloat {
        switch self {
        case .large:
            return 47
        case .small:
            return 41
        }
    }
    
    var height: CGFloat {
        switch self {
        case .large:
            return 47
        case .small:
            return 41
        }
    }
    
    var cornerRadius: CGFloat {
        switch self {
        case .large:
            return 12
        case .small:
            return 10
        }
    }
    
    var strokeWidth: CGFloat {
        switch self {
        case .large:
            return 2
        case .small:
            return 1.5
        }
    }
    
    var gridSpacing: CGFloat {
        switch self {
        case .large:
            return 7
        case .small:
            return 8
        }
    }
    
    var maxColumns: Int {
        switch self {
        case .large:
            return 4
        case .small:
            return 8
        }
    }
}
