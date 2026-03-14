import Foundation

struct ReadingList: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var itemIds: [UUID]    // LibraryItem IDs
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), name: String, itemIds: [UUID] = [], createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.itemIds = itemIds
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
