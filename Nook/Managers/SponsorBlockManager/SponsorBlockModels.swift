//
//  SponsorBlockModels.swift
//  Nook
//
//  Created by Claude on 26/03/2026.
//
//  Runtime SponsorBlock types: segments and the hash-prefix API response.
//  SponsorBlockCategory and SponsorBlockSkipOption are persisted settings and
//  live in NookSettings.
//

import Foundation
import NookSettings

// MARK: - Action Type

enum SponsorBlockActionType: String, Codable {
    case skip
    case mute
    case full
    case poi
    case chapter
}

// MARK: - Segment

struct SponsorBlockSegment: Codable, Identifiable {
    let UUID: String
    let segment: [Double]
    let category: String
    let actionType: String
    let votes: Int?
    let locked: Int?

    var id: String { UUID }
    var startTime: Double { segment.count >= 2 ? segment[0] : 0 }
    var endTime: Double { segment.count >= 2 ? segment[1] : 0 }
    var categoryEnum: SponsorBlockCategory? { SponsorBlockCategory(rawValue: category) }
    var actionEnum: SponsorBlockActionType? { SponsorBlockActionType(rawValue: actionType) }
}

// MARK: - Hash-Based API Response

/// Response from the privacy-preserving hash-prefix endpoint.
/// Each entry contains segments for a single video matching the hash prefix.
struct SponsorBlockHashResponse: Codable {
    let videoID: String
    let hash: String
    let segments: [SponsorBlockSegment]
}
