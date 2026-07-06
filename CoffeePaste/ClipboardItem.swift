import SwiftData
import Foundation
import CryptoKit

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
    var thumbnailData: Data?
    var contentHash: String?
    var createdAt: Date
    var group: ClipGroup?

    init(content: String, type: String? = "text", imageData: Data? = nil, thumbnailData: Data? = nil, contentHash: String? = nil) {
        self.id = UUID()
        self.content = content
        self.type = type
        self.imageData = imageData
        self.thumbnailData = thumbnailData
        self.contentHash = contentHash
        self.createdAt = Date()
    }
    
    static func hash(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    static func hash(of text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
