import AppKit
import ImageIO
import SwiftUI

private let panelCardSize = NSSize(width: 160, height: 130)
private let panelCardSpacing: CGFloat = 10
private let panelHorizontalInset: CGFloat = 20
private let panelVerticalInset: CGFloat = 12

enum PanelPageDirection: Equatable {
    case backward
    case forward
}

struct PanelPageRequest: Equatable {
    let id: Int
    let direction: PanelPageDirection
}

struct PanelGroupSnapshot: Identifiable, Equatable {
    let id: UUID
    let name: String
}

struct PanelClipSnapshot: Identifiable, Equatable {
    let item: ClipboardItem
    let shortcutIndex: Int?

    var id: UUID { item.id }

    static func == (lhs: PanelClipSnapshot, rhs: PanelClipSnapshot) -> Bool {
        lhs.item.id == rhs.item.id &&
        lhs.shortcutIndex == rhs.shortcutIndex &&
        lhs.item.group?.id == rhs.item.group?.id
    }
}

@MainActor
private final class PanelPreviewImageCache {
    static let shared = PanelPreviewImageCache()
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

private struct PanelDecodedPreviewImage: Sendable {
    let cgImage: CGImage
    let width: Int
    let height: Int
}

actor PanelPreviewDecodeLimiter {
    static let shared = PanelPreviewDecodeLimiter(limit: 2)

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

struct PanelClipCardView: View {
    let snapshot: PanelClipSnapshot
    let groups: [PanelGroupSnapshot]
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onAssignGroup: (UUID?) -> Void

    @State private var hovered = false
    @State private var deleteHovered = false
    @State private var decodedImage: NSImage? = nil
    @State private var previewLoadTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topBar
            contentPreview
            Spacer(minLength: 0)
            bottomBar
        }
        .frame(width: panelCardSize.width, height: panelCardSize.height)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    deleteHovered ? Color.red.opacity(0.6) :
                        (hovered ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.08)),
                    lineWidth: 1.5
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovered = $0 }
        .onTapGesture { onSelect() }
        .task(id: snapshot.id) {
            schedulePreviewLoadIfNeeded()
        }
        .onDisappear {
            previewLoadTask?.cancel()
            previewLoadTask = nil
            decodedImage = nil
        }
        .contextMenu {
            Menu("添加到分组") {
                if snapshot.item.group != nil {
                    Button("移除分组") {
                        onAssignGroup(nil)
                    }
                    Divider()
                }

                if groups.isEmpty {
                    Text("无可用分组")
                } else {
                    ForEach(groups) { group in
                        Button(group.name) {
                            onAssignGroup(group.id)
                        }
                    }
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Text(formatTime(snapshot.item.createdAt))
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var contentPreview: some View {
        ZStack {
            if snapshot.item.type == "image" {
                if let decodedImage {
                    Image(nsImage: decodedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            } else {
                Text(snapshot.item.content)
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
        guard snapshot.item.type == "image" else { return }
        guard decodedImage == nil else { return }

        if let cached = PanelPreviewImageCache.shared.get(snapshot.id) {
            decodedImage = cached
            return
        }

        guard let data = snapshot.item.thumbnailData else { return }
        let decodedPreview: PanelDecodedPreviewImage? = await Task.detached(priority: .userInitiated) {
            await PanelPreviewDecodeLimiter.shared.enter()
            defer {
                Task {
                    await PanelPreviewDecodeLimiter.shared.leave()
                }
            }

            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                guard let fallbackImage = NSImage(data: data),
                      let cgImage = fallbackImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    return nil
                }
                return PanelDecodedPreviewImage(cgImage: cgImage, width: cgImage.width, height: cgImage.height)
            }

            let options: CFDictionary = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 192,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
                return nil
            }

            return PanelDecodedPreviewImage(cgImage: cgImage, width: cgImage.width, height: cgImage.height)
        }.value

        guard let decodedPreview else { return }

        let image = NSImage(
            cgImage: decodedPreview.cgImage,
            size: NSSize(width: decodedPreview.width, height: decodedPreview.height)
        )
        PanelPreviewImageCache.shared.set(image, for: snapshot.id)
        decodedImage = image
    }

    @MainActor
    private func schedulePreviewLoadIfNeeded() {
        guard snapshot.item.type == "image" else { return }
        guard decodedImage == nil else { return }

        previewLoadTask?.cancel()
        previewLoadTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(160))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await loadImageIfNeeded()
        }
    }

    @MainActor private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    @MainActor private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter
    }()

    @MainActor private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
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
}

@MainActor
private final class PanelCollectionViewItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("PanelCollectionViewItem")

    private struct ContentSignature: Equatable {
        let id: UUID
        let content: String
        let type: String?
        let createdAt: Date
        let groupID: UUID?
        let groupSnapshots: [PanelGroupSnapshot]
    }

    private var hostingView: NSHostingView<AnyView>?
    private let badgeContainer = NSView()
    private let badgeLabel = NSTextField(labelWithString: "")
    private var lastContentSignature: ContentSignature?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        setupBadgeView()
    }

    func configure(
        snapshot: PanelClipSnapshot,
        groups: [PanelGroupSnapshot],
        onSelect: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onAssignGroup: @escaping (UUID?) -> Void
    ) {
        let contentSignature = ContentSignature(
            id: snapshot.id,
            content: snapshot.item.content,
            type: snapshot.item.type,
            createdAt: snapshot.item.createdAt,
            groupID: snapshot.item.group?.id,
            groupSnapshots: groups
        )

        if lastContentSignature != contentSignature {
            let rootView = AnyView(
                PanelClipCardView(
                    snapshot: snapshot,
                    groups: groups,
                    onSelect: onSelect,
                    onDelete: onDelete,
                    onAssignGroup: onAssignGroup
                )
            )

            if let hostingView {
                hostingView.rootView = rootView
            } else {
                let hostingView = NSHostingView(rootView: rootView)
                hostingView.translatesAutoresizingMaskIntoConstraints = false
                view.addSubview(hostingView, positioned: .below, relativeTo: badgeContainer)
                NSLayoutConstraint.activate([
                    hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                    hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    hostingView.topAnchor.constraint(equalTo: view.topAnchor),
                    hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
                ])
                self.hostingView = hostingView
            }

            lastContentSignature = contentSignature
        }

        updateBadge(shortcutIndex: nil)
    }

    private func setupBadgeView() {
        badgeContainer.translatesAutoresizingMaskIntoConstraints = false
        badgeContainer.wantsLayer = true
        badgeContainer.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        badgeContainer.layer?.cornerRadius = 4
        badgeContainer.isHidden = true

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = .systemFont(ofSize: 9, weight: .bold)
        badgeLabel.textColor = .controlAccentColor

        badgeContainer.addSubview(badgeLabel)
        view.addSubview(badgeContainer)

        NSLayoutConstraint.activate([
            badgeContainer.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            badgeContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            badgeLabel.leadingAnchor.constraint(equalTo: badgeContainer.leadingAnchor, constant: 6),
            badgeLabel.trailingAnchor.constraint(equalTo: badgeContainer.trailingAnchor, constant: -6),
            badgeLabel.topAnchor.constraint(equalTo: badgeContainer.topAnchor, constant: 2),
            badgeLabel.bottomAnchor.constraint(equalTo: badgeContainer.bottomAnchor, constant: -2)
        ])
    }

    func updateBadge(shortcutIndex: Int?) {
        guard let shortcutIndex, shortcutIndex >= 0, shortcutIndex < 9 else {
            badgeContainer.isHidden = true
            badgeLabel.stringValue = ""
            return
        }

        badgeLabel.stringValue = "⌘\(shortcutIndex + 1)"
        badgeContainer.isHidden = false
    }
}

@MainActor
struct PanelCollectionView: NSViewRepresentable {
    let items: [PanelClipSnapshot]
    let groups: [PanelGroupSnapshot]
    let pageRequest: PanelPageRequest?
    let onVisibleIndexChange: (Int) -> Void
    let onSelect: (UUID) -> Void
    let onDelete: (UUID) -> Void
    let onAssignGroup: (UUID, UUID?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = panelCardSize
        layout.minimumLineSpacing = panelCardSpacing
        layout.minimumInteritemSpacing = panelCardSpacing
        layout.sectionInset = NSEdgeInsets(
            top: panelVerticalInset,
            left: panelHorizontalInset,
            bottom: panelVerticalInset,
            right: panelHorizontalInset
        )

        let collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(PanelCollectionViewItem.self, forItemWithIdentifier: PanelCollectionViewItem.identifier)
        collectionView.dataSource = context.coordinator
        collectionView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        scrollView.documentView = collectionView

        context.coordinator.install(with: scrollView, collectionView: collectionView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(parent: self, scrollView: scrollView)
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        private var parent: PanelCollectionView
        private weak var scrollView: NSScrollView?
        private weak var collectionView: NSCollectionView?
        private var lastPageRequestID: Int?
        private var lastVisibleIndex = 0

        init(parent: PanelCollectionView) {
            self.parent = parent
        }

        func install(with scrollView: NSScrollView, collectionView: NSCollectionView) {
            self.scrollView = scrollView
            self.collectionView = collectionView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        func update(parent: PanelCollectionView, scrollView: NSScrollView) {
            let oldItems = self.parent.items
            let oldGroups = self.parent.groups
            self.parent = parent

            if oldItems.map(\.id) != parent.items.map(\.id) {
                collectionView?.reloadData()
            } else if oldItems != parent.items || oldGroups != parent.groups {
                reconfigureVisibleItems()
            }

            if let pageRequest = parent.pageRequest, pageRequest.id != lastPageRequestID {
                lastPageRequestID = pageRequest.id
                performPage(pageRequest.direction, in: scrollView)
            } else {
                notifyVisibleIndex()
            }
        }

        func numberOfSections(in collectionView: NSCollectionView) -> Int {
            1
        }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.items.count
        }

        func collectionView(
            _ collectionView: NSCollectionView,
            itemForRepresentedObjectAt indexPath: IndexPath
        ) -> NSCollectionViewItem {
            let item = collectionView.makeItem(
                withIdentifier: PanelCollectionViewItem.identifier,
                for: indexPath
            )

            guard let item = item as? PanelCollectionViewItem else {
                return item
            }

            let snapshot = parent.items[indexPath.item]
            item.configure(
                snapshot: snapshot,
                groups: parent.groups,
                onSelect: { [weak self] in self?.parent.onSelect(snapshot.id) },
                onDelete: { [weak self] in self?.parent.onDelete(snapshot.id) },
                onAssignGroup: { [weak self] groupID in
                    self?.parent.onAssignGroup(snapshot.id, groupID)
                }
            )
            item.updateBadge(shortcutIndex: shortcutIndex(for: indexPath.item))
            return item
        }

        @objc
        private func boundsDidChange() {
            notifyVisibleIndex()
        }

        private func notifyVisibleIndex() {
            guard let collectionView else { return }
            let firstIndex = collectionView
                .indexPathsForVisibleItems()
                .map(\.item)
                .min() ?? 0
            guard firstIndex != lastVisibleIndex else { return }
            lastVisibleIndex = firstIndex
            parent.onVisibleIndexChange(firstIndex)
        }

        private func reconfigureVisibleItems() {
            guard let collectionView else { return }
            collectionView.visibleItems().forEach { item in
                guard let item = item as? PanelCollectionViewItem,
                      let indexPath = collectionView.indexPath(for: item),
                      indexPath.item < parent.items.count else { return }
                let snapshot = parent.items[indexPath.item]
                item.configure(
                    snapshot: snapshot,
                    groups: parent.groups,
                    onSelect: { [weak self] in self?.parent.onSelect(snapshot.id) },
                    onDelete: { [weak self] in self?.parent.onDelete(snapshot.id) },
                    onAssignGroup: { [weak self] groupID in
                        self?.parent.onAssignGroup(snapshot.id, groupID)
                    }
                )
                item.updateBadge(shortcutIndex: shortcutIndex(for: indexPath.item))
            }
        }

        private func shortcutIndex(for itemIndex: Int) -> Int? {
            guard itemIndex < parent.items.count else { return nil }
            return parent.items[itemIndex].shortcutIndex
        }

        private func performPage(_ direction: PanelPageDirection, in scrollView: NSScrollView) {
            guard let collectionView else { return }
            
            let availableWidth = max(0, scrollView.contentView.bounds.width - panelHorizontalInset * 2)
            let visibleCount = max(1, Int((availableWidth + panelCardSpacing) / (panelCardSize.width + panelCardSpacing)))
            let pageWidth = CGFloat(visibleCount) * (panelCardSize.width + panelCardSpacing)
            
            // 用户要求：每次只翻 0.8 页，不要翻太多
            let scrollAmount = pageWidth * 0.8
            
            var newOffset = scrollView.contentView.bounds.origin
            if direction == .forward {
                newOffset.x += scrollAmount
            } else {
                newOffset.x -= scrollAmount
            }
            
            // 计算最大可能的偏移量
            let contentWidth = collectionView.collectionViewLayout?.collectionViewContentSize.width ?? 0
            let maxOffsetX = max(0, contentWidth - scrollView.contentView.bounds.width)
            newOffset.x = max(0, min(newOffset.x, maxOffsetX))
            
            // 使用 NSAnimationContext 添加平滑动画
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.25 // 0.25秒的平滑过渡
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                scrollView.contentView.animator().setBoundsOrigin(newOffset)
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }, completionHandler: { [weak self] in
                guard let self = self else { return }
                // 动画完成后更新我们自己的 lastVisibleIndex
                let firstVisibleIndex = Int(floor(newOffset.x / (panelCardSize.width + panelCardSpacing)))
                self.lastVisibleIndex = max(0, min(self.parent.items.count - 1, firstVisibleIndex))
                self.parent.onVisibleIndexChange(self.lastVisibleIndex)
            })
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
