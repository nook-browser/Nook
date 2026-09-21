// Licensed under GPL-3.0. See LICENSE.
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

public enum SponsorBlockActionType: String, Codable {
    case skip
    case mute
    case full
    case poi
    case chapter
}

// MARK: - Segment

public struct SponsorBlockSegment: Codable, Identifiable {
    public let UUID: String
    public let segment: [Double]
    public let category: String
    public let actionType: String
    public let votes: Int?
    public let locked: Int?

    public var id: String { UUID }
    public var startTime: Double { segment.count >= 2 ? segment[0] : 0 }
    public var endTime: Double { segment.count >= 2 ? segment[1] : 0 }
    public var categoryEnum: SponsorBlockCategory? { SponsorBlockCategory(rawValue: category) }
    public var actionEnum: SponsorBlockActionType? { SponsorBlockActionType(rawValue: actionType) }
}

// MARK: - Hash-Based API Response

/// Response from the privacy-preserving hash-prefix endpoint.
/// Each entry contains segments for a single video matching the hash prefix.
/// The live endpoint returns only `videoID` and `segments`; `hash` is documented
/// but omitted in practice, so it stays optional and the video is matched by id.
struct SponsorBlockHashResponse: Codable {
    let videoID: String
    let hash: String?
    let segments: [SponsorBlockSegment]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        videoID = try c.decode(String.self, forKey: .videoID)
        hash = try c.decodeIfPresent(String.self, forKey: .hash)
        // The API is a third party: a range like [0, 1e9] would skip any video to
        // its end. The comparisons also reject NaN and infinity.
        segments = try c.decode([SponsorBlockSegment].self, forKey: .segments).filter {
            $0.segment.count == 2 && $0.segment[0] >= 0
                && $0.segment[0] < $0.segment[1] && $0.segment[1] < 86400
        }
    }
}
