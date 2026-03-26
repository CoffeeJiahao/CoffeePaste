import SwiftData
import Foundation

@Model
final class ClipGroup {
    var id: UUID
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .nullify, inverse: \ClipboardItem.group) var items: [ClipboardItem]? = []
    
    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}

@Model
class ClipboardItem {
    var id: UUID
    var content: String
    var type: String?
    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?
    var createdAt: Date
    var group: ClipGroup?

    init(content: String, type: String? = "text", imageData: Data? = nil, thumbnailData: Data? = nil) {
        self.id = UUID()
        self.content = content
        self.type = type
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.createdAt = Date()
    }
}
