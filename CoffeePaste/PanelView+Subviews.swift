import SwiftUI
import SwiftData
import ImageIO

@MainActor
private final class ClipPreviewImageCache {
    static let shared = ClipPreviewImageCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 80
    }

    func get(_ id: UUID) -> NSImage? {
        cache.object(forKey: id.uuidString as NSString)
    }

    func set(_ image: NSImage, for id: UUID) {
        cache.setObject(image, forKey: id.uuidString as NSString)
    }
}

private struct DecodedPreviewImage: Sendable {
    let cgImage: CGImage
    let width: Int
    let height: Int
}

actor ClipPreviewDecodeLimiter {
    static let shared = ClipPreviewDecodeLimiter(limit: 2)

    private let limit: Int
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func enter() async {
        if inFlight < limit {
            inFlight += 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func leave() {
        if waiters.isEmpty {
            inFlight = max(0, inFlight - 1)
            return
        }

        let continuation = waiters.removeFirst()
        continuation.resume()
    }
}

@MainActor
@Observable
final class ShortcutState {
    static let shared = ShortcutState()
    var isCommandPressed = false
    
    func startMonitoring() {
        // Command modifier updates are handled directly by CustomPanel.sendEvent(_:)
    }
    
    func stopMonitoring() {
        // No-op; kept for call-site compatibility.
    }
}

// MARK: - 分组按钮
struct GroupButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor : Color.primary.opacity(0.05))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 单张卡片
struct ClipCard: View {
    let item: ClipboardItem
    let shouldShowPreview: Bool
    let shortcutIndex: Int?
    let groups: [ClipGroup]
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false
    @State private var deleteHovered = false
    @State private var decodedImage: NSImage? = nil
    @State private var isAnimating = false
    @State private var previewLoadTask: Task<Void, Never>? = nil
    @Environment(\.modelContext) private var modelContext

    private func reportPreviewTask() {
        guard item.type == "image" else { return }
        debugReportImageScrollEvent(
            hypothesisId: "A",
            location: "PanelView+Subviews.swift:ClipCard.task",
            message: "image preview task fired",
            data: [
                "itemId": item.id.uuidString,
                "shouldShowPreview": String(shouldShowPreview),
                "hasDecodedImage": String(decodedImage != nil)
            ]
        )
    }

    private func reportCacheHit() {
        debugReportImageScrollEvent(
            hypothesisId: "B",
            location: "PanelView+Subviews.swift:loadImageIfNeeded",
            message: "preview cache hit",
            data: [
                "itemId": item.id.uuidString
            ]
        )
    }

    private func reportDecodeFinished(
        _ image: NSImage?,
        thumbnailBytes: Int,
        fetchDataMs: Double,
        decodeMs: Double
    ) {
        debugReportImageScrollEvent(
            hypothesisId: "B",
            location: "PanelView+Subviews.swift:loadImageIfNeeded",
            message: "preview decode finished",
            data: [
                "itemId": item.id.uuidString,
                "thumbnailBytes": String(thumbnailBytes),
                "decoded": String(image != nil),
                "pixelWidth": String(Int(image?.size.width ?? 0)),
                "pixelHeight": String(Int(image?.size.height ?? 0)),
                "fetchDataMs": String(format: "%.2f", fetchDataMs),
                "decodeMs": String(format: "%.2f", decodeMs)
            ]
        )
    }

    private func reportPreviewSkipped() {
        debugReportImageScrollEvent(
            hypothesisId: "E",
            location: "PanelView+Subviews.swift:updatePreviewState",
            message: "preview skipped while card hidden",
            data: [
                "itemId": item.id.uuidString,
                "hasDecodedImage": String(decodedImage != nil)
            ]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            contentPreview
            Spacer(minLength: 0)
            bottomBar
        }
        .frame(width: 160, height: 130)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(deleteHovered ? Color.red.opacity(0.6) : (hovered ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.08)),
                        lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        .onHover { hovered = $0 }
        .onTapGesture { onSelect() }
        .task(id: item.id) {
            schedulePreviewLoadIfNeeded()
        }
        .onChange(of: shouldShowPreview) { _, newValue in
            if !newValue {
                previewLoadTask?.cancel()
                previewLoadTask = nil
                return
            }
            schedulePreviewLoadIfNeeded()
        }
        .onDisappear {
            previewLoadTask?.cancel()
            previewLoadTask = nil
            releasePreview()
        }
        .contextMenu {
            Menu("添加到分组") {
                if item.group != nil {
                    Button("移除分组") {
                        item.group = nil
                        try? modelContext.save()
                    }
                    Divider()
                }
                
                if groups.isEmpty {
                    Text("无可用分组")
                } else {
                    ForEach(groups) { group in
                        Button(group.name) {
                            item.group = group
                            try? modelContext.save()
                        }
                    }
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text(formatTime(item.createdAt))
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
            
            Spacer()
            
            if let shortcutIndex, shortcutIndex >= 0 && shortcutIndex < 9 {
                Text("⌘\(shortcutIndex + 1)")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .foregroundColor(.accentColor)
                    .cornerRadius(4)
                    .opacity(0.8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
    
    @MainActor private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    @MainActor private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd"
        return f
    }()

    @MainActor private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f
    }()

    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return Self.timeFormatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "昨天"
        }
        let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
        if daysAgo < 7 {
            return Self.weekdayFormatter.string(from: date)
        }
        return Self.dateFormatter.string(from: date)
    }

    @ViewBuilder
    private var contentPreview: some View {
        ZStack {
            if item.type == "image" {
                if shouldShowPreview, let image = decodedImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            } else {
                Text(item.content)
                    .font(.system(size: 12))
                    .lineLimit(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.05))
        .cornerRadius(6)
        .padding(.horizontal, 12)
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            if hovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(deleteHovered ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .onHover { deleteHovered = $0 }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 6)
    }

    @MainActor
    private func loadImageIfNeeded() async {
        guard item.type == "image" else { return }
        guard decodedImage == nil else { return } // 只解码一次，避免反复 reload 导致卡顿
        if let cached = ClipPreviewImageCache.shared.get(item.id) {
            // #region debug-point B:image-cache-hit
            reportCacheHit()
            // #endregion
            decodedImage = cached
            return
        }
        // 预览严格只使用缩略图，避免卡片滚动时回退到原图解码。
        let fetchStartedAt = DispatchTime.now().uptimeNanoseconds
        guard let data = item.thumbnailData else { return }
        let fetchDataMs = Double(DispatchTime.now().uptimeNanoseconds - fetchStartedAt) / 1_000_000

        let startedAt = DispatchTime.now().uptimeNanoseconds
        let decodedPreview: DecodedPreviewImage? = await Task.detached(priority: .userInitiated) {
            await ClipPreviewDecodeLimiter.shared.enter()
            defer {
                Task {
                    await ClipPreviewDecodeLimiter.shared.leave()
                }
            }

            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                guard let fallbackImage = NSImage(data: data),
                      let cgImage = fallbackImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    return nil
                }
                return DecodedPreviewImage(
                    cgImage: cgImage,
                    width: cgImage.width,
                    height: cgImage.height
                )
            }

            let options: CFDictionary = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 192,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary

            if let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
                return DecodedPreviewImage(
                    cgImage: cgImage,
                    width: cgImage.width,
                    height: cgImage.height
                )
            }

            guard let fallbackImage = NSImage(data: data),
                  let cgImage = fallbackImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return nil
            }
            return DecodedPreviewImage(
                cgImage: cgImage,
                width: cgImage.width,
                height: cgImage.height
            )
        }.value
        let decodeMs = Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        let nsImage = decodedPreview.map {
            NSImage(cgImage: $0.cgImage, size: NSSize(width: $0.width, height: $0.height))
        }

        // #region debug-point B:image-decode-finished
        reportDecodeFinished(
            nsImage,
            thumbnailBytes: data.count,
            fetchDataMs: fetchDataMs,
            decodeMs: decodeMs
        )
        // #endregion

        if let nsImage {
            ClipPreviewImageCache.shared.set(nsImage, for: item.id)
        }

        self.decodedImage = nsImage
    }

    @MainActor
    private func updatePreviewState() async {
        guard item.type == "image" else { return }
        guard shouldShowPreview else {
            // #region debug-point E:preview-skipped
            reportPreviewSkipped()
            // #endregion
            return
        }
        await loadImageIfNeeded()
    }

    @MainActor
    private func schedulePreviewLoadIfNeeded() {
        guard item.type == "image" else { return }
        guard shouldShowPreview else { return }
        guard decodedImage == nil else { return }

        // Debounce: fast scrolling should not trigger lots of short-lived loads.
        previewLoadTask?.cancel()
        previewLoadTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(160))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            guard shouldShowPreview else { return }

            // #region debug-point A:preview-task
            reportPreviewTask()
            // #endregion

            await updatePreviewState()
        }
    }

    @MainActor
    private func releasePreview() {
        decodedImage = nil
    }
}

// MARK: - 毛玻璃
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
