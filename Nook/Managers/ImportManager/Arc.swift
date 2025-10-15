//
//  Arc.swift
//  Nook
//
//  Created by Maciek Bagiński on 29/09/2025.
//

import Foundation
import Combine

// MARK: - JSON Models
struct SidebarData: Codable {
    let version: Int
    let sidebar: Sidebar
}

struct Sidebar: Codable {
    let containers: [SidebarContainer]
}

struct SidebarContainer: Codable {
    let global: GlobalContainer?
    let items: [SidebarItem]?
    let spaces: [SpaceInfo]?
    let topAppsContainerIDs: [TopAppContainer]?
    
    private enum CodingKeys: String, CodingKey {
        case global, items, spaces, topAppsContainerIDs
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        global = try container.decodeIfPresent(GlobalContainer.self, forKey: .global)
        topAppsContainerIDs = try container.decodeIfPresent([TopAppContainer].self, forKey: .topAppsContainerIDs)
        
        if container.contains(.items) {
            do {
                var itemsContainer = try container.nestedUnkeyedContainer(forKey: .items)
                var itemsList: [SidebarItem] = []
                
                while !itemsContainer.isAtEnd {
                    if !itemsContainer.isAtEnd {
                        _ = try itemsContainer.decode(String.self)
                    }
                    
                    if !itemsContainer.isAtEnd {
                        do {
                            let item = try itemsContainer.decode(SidebarItem.self)
                            itemsList.append(item)
                        } catch {
                            _ = try? itemsContainer.decode(AnyCodable.self)
                        }
                    }
                }
                
                items = itemsList.isEmpty ? nil : itemsList
            } catch {
                items = nil
            }
        } else {
            items = nil
        }
        
        if container.contains(.spaces) {
            do {
                var spacesContainer = try container.nestedUnkeyedContainer(forKey: .spaces)
                var spacesList: [SpaceInfo] = []
                
                while !spacesContainer.isAtEnd {
                    if !spacesContainer.isAtEnd {
                        _ = try spacesContainer.decode(String.self)
                    }
                    
                    if !spacesContainer.isAtEnd {
                        do {
                            let space = try spacesContainer.decode(SpaceInfo.self)
                            spacesList.append(space)
                        } catch {
                            _ = try? spacesContainer.decode(AnyCodable.self)
                        }
                    }
                }
                
                spaces = spacesList.isEmpty ? nil : spacesList
            } catch {
                spaces = nil
            }
        } else {
            spaces = nil
        }
    }
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

struct AnyCodable: Codable {
    let value: Any
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let string = try? container.decode(String.self) {
            value = string
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
          } else if let jsonData = try? container.decode(Data.self) {
            // Try to decode as JSON for complex types
            if let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) {
                value = jsonObject
            } else {
                value = NSNull()
            }
        } else {
            // Default fallback
            throw DecodingError.typeMismatch(AnyCodable.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Cannot decode AnyCodable"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let string = value as? String {
            try container.encode(string)
        } else if let bool = value as? Bool {
            try container.encode(bool)
        } else if let int = value as? Int {
            try container.encode(int)
        } else if let double = value as? Double {
            try container.encode(double)
        } else if let dict = value as? [String: Any] {
            let codableDict = dict.mapValues { AnyCodable($0) }
            try container.encode(codableDict)
        } else if let array = value as? [Any] {
            let codableArray = array.map { AnyCodable($0) }
            try container.encode(codableArray)
        } else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode AnyCodable"))
        }
    }
    
    init(_ value: Any) {
        self.value = value
    }
}

extension Dictionary where Key == String, Value == Any {
    func mapValues<T>(_ transform: (Value) throws -> T) rethrows -> [Key: T] {
        var result: [Key: T] = [:]
        for (key, value) in self {
            result[key] = try transform(value)
        }
        return result
    }
}

struct GlobalContainer: Codable {}
struct TopAppContainer: Codable {}

struct SidebarItem: Codable {
    let title: String?
    let id: String
    let childrenIds: [String]
    let data: ItemData
    let parentID: String?
    let originatingDevice: String
    let createdAt: Double
    let isUnread: Bool
}

struct ItemData: Codable {
    let tab: TabData?
    let list: ListData?
    let itemContainer: ItemContainer?
}

struct TabData: Codable {
    let savedMuteStatus: String?
    let referrerID: String?
    let savedTitle: String?
    let activeTabBeforeCreationID: String?
    let timeLastActiveAt: Double?
    let savedURL: String?
}

struct ListData: Codable {
    let customInfo: ListCustomInfo?
    let automaticLiveFolderData: AutomaticLiveFolderData?
}

struct ListCustomInfo: Codable {
    let iconType: IconType?
}

struct AutomaticLiveFolderData: Codable {}

struct ItemContainer: Codable {
    let containerType: ContainerType?
}

struct ContainerType: Codable {
    let spaceItems: SpaceItems?
    let topApps: TopApps?
}

struct SpaceItems: Codable {
    let _0: String
}

struct TopApps: Codable {
    let _0: DefaultTopApp?
}

struct DefaultTopApp: Codable {
    let `default`: EmptyObject?
}

struct EmptyObject: Codable {}

struct SpaceInfo: Codable {
    let customInfo: CustomInfo?
    let title: String
    let id: String
    let containerIDs: [String]?
}

struct CustomInfo: Codable {
    let iconType: IconType?
}

struct IconType: Codable {
    let icon: String?
    let emoji: Int?
    let emoji_v2: String?
}

// MARK: - Arc Models
struct ArcImportResult {
    let topTabs: [ArcTab]
    let spaces: [ArcSpace]
}

struct ArcSpace {
    let id: String
    let title: String
    let icon: String?
    let emoji: String?
    let tabs: [ArcTab]
    let folders: [ArcFolder]
}

struct ArcTab {
    let id: String
    let title: String
    let url: String
    let domain: String
    let parentID: String?
    let isUnread: Bool
}

struct ArcFolder {
    let id: String
    let title: String
    let tabs: [ArcTab]
    let parentID: String?
}

// MARK: - Parser Function
func parseArcSidebarData(from fileURL: URL) throws -> ArcImportResult {
    let data = try Data(contentsOf: fileURL)
    let sidebarData = try JSONDecoder().decode(SidebarData.self, from: data)
    
    var spacesDict: [String: (id: String, title: String, icon: String?, emoji: String?)] = [:]
    var allItems: [String: SidebarItem] = [:]
    var containerToSpaceMap: [String: String] = [:]
    
    for container in sidebarData.sidebar.containers {
        if let spacesList = container.spaces {
            for spaceInfo in spacesList {
                if spacesDict[spaceInfo.id] == nil {
                    spacesDict[spaceInfo.id] = (
                        id: spaceInfo.id,
                        title: spaceInfo.title,
                        icon: spaceInfo.customInfo?.iconType?.icon,
                        emoji: spaceInfo.customInfo?.iconType?.emoji_v2
                    )
                }
                
                if let containerIDs = spaceInfo.containerIDs {
                    for containerID in containerIDs {
                        containerToSpaceMap[containerID] = spaceInfo.id
                    }
                }
            }
        }
        
        if let itemsList = container.items {
            for item in itemsList {
                allItems[item.id] = item
                
                if let containerType = item.data.itemContainer?.containerType?.spaceItems {
                    containerToSpaceMap[item.id] = containerType._0
                }
            }
        }
    }
    
    var arcSpaces: [ArcSpace] = []
    var topTabs: [ArcTab] = []
    
    for (_, item) in allItems {
        if let tabData = item.data.tab {
            let url = tabData.savedURL ?? ""
            let domain = extractDomain(from: url)
            let title = item.title ?? tabData.savedTitle ?? ""
            
            let tab = ArcTab(
                id: item.id,
                title: title,
                url: url,
                domain: domain,
                parentID: item.parentID,
                isUnread: item.isUnread
            )
            
            if let parentID = item.parentID,
               (parentID.contains("topApps") || allItems[parentID]?.data.itemContainer?.containerType?.topApps != nil) {
                topTabs.append(tab)
            }
        }
    }
    
    for spaceInfo in spacesDict.values {
        var spaceTabs: [ArcTab] = []
        var spaceFolders: [ArcFolder] = []
        
        for (_, item) in allItems {
            let spaceContext = findSpaceContext(for: item.parentID, in: containerToSpaceMap, spaces: Array(spacesDict.values))
            
            guard spaceContext == spaceInfo.id else { continue }
            
            if let tabData = item.data.tab {
                if let parentID = item.parentID,
                   (parentID.contains("topApps") || allItems[parentID]?.data.itemContainer?.containerType?.topApps != nil) {
                    continue
                }
                
                let url = tabData.savedURL ?? ""
                let domain = extractDomain(from: url)
                let title = item.title ?? tabData.savedTitle ?? ""
                
                let tab = ArcTab(
                    id: item.id,
                    title: title,
                    url: url,
                    domain: domain,
                    parentID: item.parentID,
                    isUnread: item.isUnread
                )
                
                spaceTabs.append(tab)
                
            } else if (item.data.list != nil || item.data.itemContainer != nil) && !item.childrenIds.isEmpty {
                let folderTabs = item.childrenIds.compactMap { childId -> ArcTab? in
                    guard let childItem = allItems[childId],
                          let childTabData = childItem.data.tab else { return nil }
                    
                    let url = childTabData.savedURL ?? ""
                    let title = childItem.title ?? childTabData.savedTitle ?? ""
                    
                    return ArcTab(
                        id: childItem.id,
                        title: title,
                        url: url,
                        domain: extractDomain(from: url),
                        parentID: childItem.parentID,
                        isUnread: childItem.isUnread
                    )
                }
                
                if !folderTabs.isEmpty {
                    let folder = ArcFolder(
                        id: item.id,
                        title: item.title ?? "",
                        tabs: folderTabs,
                        parentID: item.parentID
                    )
                    spaceFolders.append(folder)
                }
            }
        }
        
        let arcSpace = ArcSpace(
            id: spaceInfo.id,
            title: spaceInfo.title,
            icon: spaceInfo.icon,
            emoji: spaceInfo.emoji,
            tabs: spaceTabs,
            folders: spaceFolders
        )
        
        arcSpaces.append(arcSpace)
    }
    
    return ArcImportResult(topTabs: topTabs, spaces: arcSpaces)
}

private func extractDomain(from url: String) -> String {
    guard let url = URL(string: url) else { return "" }
    return url.host ?? ""
}

private func findSpaceContext(for parentID: String?, in containerToSpaceMap: [String: String], spaces: [(id: String, title: String, icon: String?, emoji: String?)]) -> String? {
    guard let parentID = parentID else { return nil }
    return containerToSpaceMap[parentID]
}
