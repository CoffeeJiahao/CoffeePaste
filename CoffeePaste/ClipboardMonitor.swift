import AppKit
import SwiftData

class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    private let modelContext: ModelContext
    
    // 从 UserDefaults 读取配置
    private var maxItems: Int {
        UserDefaults.standard.bool(forKey: "isMaxItemsInfinite") ? Int.max : UserDefaults.standard.integer(forKey: "maxItems")
    }
    
    private var maxDaysValue: Int? {
        UserDefaults.standard.bool(forKey: "isMaxDaysInfinite") ? nil : UserDefaults.standard.integer(forKey: "maxDays")
    }

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        let desc = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        let latest = try? modelContext.fetch(desc).first

        // 先检查是否是图片
        if let tiffData = pb.data(forType: .tiff) ?? pb.data(forType: .png) {
            // 去重：如果最近一条也是相同的图片则跳过
            if latest?.type == "image", latest?.imageData == tiffData { return }
            
            let item = ClipboardItem(content: "[图片]", type: "image", imageData: tiffData)
            modelContext.insert(item)
            try? modelContext.save()
            trim()
            return
        }

        // 否则检查是否是文本
        guard let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        // 去重：和最近一条一样就跳过
        if latest?.content == text, latest?.type != "image" { return }

        modelContext.insert(ClipboardItem(content: text, type: "text"))
        try? modelContext.save()
        trim()
    }

    private func trim() {
        // 1. 按数量修剪
        let countDesc = FetchDescriptor<ClipboardItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let all = try? modelContext.fetch(countDesc), all.count > maxItems {
            all.suffix(from: maxItems).forEach { modelContext.delete($0) }
        }

        // 2. 按时间修剪
        if let days = maxDaysValue {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let timePredicate = #Predicate<ClipboardItem> { item in
                item.createdAt < cutoffDate
            }
            let timeDesc = FetchDescriptor<ClipboardItem>(predicate: timePredicate)
            if let oldItems = try? modelContext.fetch(timeDesc) {
                oldItems.forEach { modelContext.delete($0) }
            }
        }
        
        try? modelContext.save()
    }
}
