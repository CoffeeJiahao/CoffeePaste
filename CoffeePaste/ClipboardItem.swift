import SwiftData
import Foundation

@Model
class ClipboardItem {
    var id: UUID
    var content: String
    var type: String? // "text" or "image"
    @Attribute(.externalStorage) var imageData: Data?
    var createdAt: Date

    init(content: String, type: String? = "text", imageData: Data? = nil) {
        self.id = UUID()
        self.content = content
        self.type = type
        self.imageData = imageData
        self.createdAt = Date()
    }
}
