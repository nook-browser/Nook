import Foundation
import SwiftData

@Model
final class ExtensionStorageEntity {
    @Attribute(.unique) var id: UUID
    var extensionId: String
    var key: String
    var valueData: Data
    var updatedAt: Date

    init(id: UUID = UUID(), extensionId: String, key: String, valueData: Data, updatedAt: Date = Date()) {
        self.id = id
        self.extensionId = extensionId
        self.key = key
        self.valueData = valueData
        self.updatedAt = updatedAt
    }
}

