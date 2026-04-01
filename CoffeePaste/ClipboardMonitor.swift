import AppKit
import SwiftData

@MainActor
final class ClipboardMonitor {
    private var task: Task<Void, Never>?
    private var lastChangeCount: Int
    private let modelContext: ModelContext
    
    private var cachedMaxItems: Int = 200
    private var cachedMaxDays: Int? = 30
    private var configObserver: NSObjectProtocol?

    private var maxItems: Int { cachedMaxItems }
    private var maxDaysValue: Int? { cachedMaxDays }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.lastChangeCount = NSPasteboard.general.changeCount
        loadConfig()
        observeConfigChanges()
    }
    
    private func loadConfig() {
        let isMaxItemsInfinite = UserDefaults.standard.bool(forKey: "isMaxItemsInfinite")
        cachedMaxItems = isMaxItemsInfinite ? Int.max : max(UserDefaults.standard.integer(forKey: "maxItems"), 10)
        
        let isMaxDaysInfinite = UserDefaults.standard.bool(forKey: "isMaxDaysInfinite")
        cachedMaxDays = isMaxDaysInfinite ? nil : UserDefaults.standard.integer(forKey: "maxDays")
    }
    
    private func observeConfigChanges() {
        configObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.loadConfig()
            }
        }
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.5))
                self?.check()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        let desc = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let latest = try? modelContext.fetch(desc).first

        if let tiffData = pb.data(forType: .tiff) ?? pb.data(forType: .png) {
            if latest?.type == "image", latest?.imageData == tiffData { return }
            
            let thumbnail = Self.generateThumbnail(from: tiffData, maxSize: 240)
            let item = ClipboardItem(content: "[图片]", type: "image", imageData: tiffData, thumbnailData: thumbnail)
            modelContext.insert(item)
            try? modelContext.save()
            trim()
            return
        }

        // 否则检查是否是文本
        guard let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if text.count < 1024 {
            var descriptor = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { item in
                    item.content == text && item.type == "text"
                }
            )
            descriptor.fetchLimit = 1
            if let existing = try? modelContext.fetch(descriptor).first {
                existing.createdAt = Date()
                try? modelContext.save()
                return
            }
        } else {
            if latest?.content == text, latest?.type == "text" { return }
        }

        modelContext.insert(ClipboardItem(content: text, type: "text"))
        try? modelContext.save()
        trim()
    }

    private func trim() {
        if maxItems < Int.max {
            var deleteDesc = FetchDescriptor<ClipboardItem>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            deleteDesc.fetchOffset = maxItems
            if let toDelete = try? modelContext.fetch(deleteDesc) {
                toDelete.forEach { modelContext.delete($0) }
            }
        }

        if let days = maxDaysValue {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let timeDesc = FetchDescriptor<ClipboardItem>(
                predicate: #Predicate { $0.createdAt < cutoffDate }
            )
            if let oldItems = try? modelContext.fetch(timeDesc) {
                oldItems.forEach { modelContext.delete($0) }
            }
        }
        
        try? modelContext.save()
    }
    
    private static func generateThumbnail(from data: Data, maxSize: CGFloat) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let originalSize = image.size
        
        guard originalSize.width > maxSize || originalSize.height > maxSize else { return data }
        
        let ratio = min(maxSize / originalSize.width, maxSize / originalSize.height)
        let newSize = NSSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
        
        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: originalSize), operation: .copy, fraction: 1.0)
        resizedImage.unlockFocus()
        
        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        
        return pngData
    }
}
