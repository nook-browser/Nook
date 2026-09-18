// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  HistoryEntity.swift
//  Nook
//
//  Created by Jonathan Caudill on 09/08/2025.
//

import Foundation
import SwiftData

@Model
public final class HistoryEntity {
    #Index<HistoryEntity>([\.url, \.profileId], [\.lastVisited])
    @Attribute(.unique) public var id: UUID
    public var url: String
    public var title: String
    public var visitDate: Date
    public var tabId: UUID?
    public var visitCount: Int
    public var lastVisited: Date
    // Optional profile association for backward compatibility during migration
    public var profileId: UUID?
    
    public init(
        id: UUID = UUID(),
        url: String,
        title: String,
        visitDate: Date = Date(),
        tabId: UUID? = nil,
        visitCount: Int = 1,
        lastVisited: Date = Date(),
        profileId: UUID? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.visitDate = visitDate
        self.tabId = tabId
        self.visitCount = visitCount
        self.lastVisited = lastVisited
        self.profileId = profileId
    }
}
