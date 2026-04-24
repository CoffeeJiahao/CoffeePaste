import SwiftUI
import SwiftData

private let maxDisplayCount = 100
private let cardWidth: CGFloat = 160
private let cardSpacing: CGFloat = 10
private let horizontalPadding: CGFloat = 20
private let pageSize = 9

private final class ScrollMetricsStore {
    var latestOffset: CGFloat = 0
}

// #region debug-point A:scroll-jank-reporter
@MainActor
func debugReportScrollJankEvent(
    hypothesisId: String,
    location: String,
    message: String,
    data: [String: String] = [:]
) {
    // Debug logging can easily destroy scroll performance; keep it opt-in.
    guard UserDefaults.standard.bool(forKey: "debugScrollJank") else { return }

    struct Cache {
        static var isInitialized = false
        static var url: URL?
    }

    let envPath = URL(fileURLWithPath: ".dbg/scroll-jank.env")
    let fallbackURL = "http://127.0.0.1:7777/event"

    if !Cache.isInitialized {
        Cache.isInitialized = true

        var serverURL = fallbackURL
        if let envContent = try? String(contentsOf: envPath),
           let matchedLine = envContent
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("DEBUG_SERVER_URL=") }) {
            serverURL = String(matchedLine.dropFirst("DEBUG_SERVER_URL=".count))
        }

        Cache.url = URL(string: serverURL)
    }
    guard let url = Cache.url else { return }

    let payload: [String: Any] = [
        "sessionId": "scroll-jank",
        "runId": "post-fix",
        "hypothesisId": hypothesisId,
        "location": location,
        "msg": "[DEBUG] \(message)",
        "data": data,
        "ts": Int(Date().timeIntervalSince1970 * 1000)
    ]
    guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    Task.detached {
        URLSession.shared.dataTask(with: request).resume()
    }
}
// #endregion

// #region debug-point E:image-scroll-jank-reporter
@MainActor
func debugReportImageScrollEvent(
    hypothesisId: String,
    location: String,
    message: String,
    data: [String: String] = [:]
) {
    guard UserDefaults.standard.bool(forKey: "debugImageScrollJank") else { return }

    struct Cache {
        static var isInitialized = false
        static var url: URL?
        static var sessionId = "image-scroll-jank"
    }

    let envPath = URL(fileURLWithPath: ".dbg/image-scroll-jank.env")
    let fallbackURL = "http://127.0.0.1:7777/event"

    if !Cache.isInitialized {
        Cache.isInitialized = true

        var serverURL = fallbackURL
        if let envContent = try? String(contentsOf: envPath, encoding: .utf8) {
            for line in envContent.split(separator: "\n") {
                if line.hasPrefix("DEBUG_SERVER_URL=") {
                    serverURL = String(line.dropFirst("DEBUG_SERVER_URL=".count))
                } else if line.hasPrefix("DEBUG_SESSION_ID=") {
                    Cache.sessionId = String(line.dropFirst("DEBUG_SESSION_ID=".count))
                }
            }
        }

        Cache.url = URL(string: serverURL)
    }
    guard let url = Cache.url else { return }

    let payload: [String: Any] = [
        "sessionId": Cache.sessionId,
        "runId": "post-fix",
        "hypothesisId": hypothesisId,
        "location": location,
        "msg": "[DEBUG] \(message)",
        "data": data,
        "ts": Int(Date().timeIntervalSince1970 * 1000)
    ]
    guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body
    Task.detached {
        URLSession.shared.dataTask(with: request).resume()
    }
}
// #endregion

struct PanelView: View {
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]
    @Query(sort: \ClipGroup.createdAt) private var groups: [ClipGroup]
    @Environment(\.modelContext) private var modelContext

    @State private var search = ""
    @State private var showOnlyImages = false
    @State private var showOnlyText = false
    @FocusState private var isSearchFocused: Bool

    @State private var selectedGroup: ClipGroup? = nil
    @State private var isAddingGroup = false
    @State private var newGroupName = ""
    @FocusState private var isNewGroupFocused: Bool
    @State private var groupToDelete: ClipGroup? = nil
    @State private var showDeleteAlert = false
    @State private var visibleBaseIndexState = 0
    @State private var shortcutBaseIndexState = 0
    @State private var isCommandPressed = false
    @State private var filteredItems: [ClipboardItem] = []
    @State private var pageRequestID = 0
    @State private var pageRequestDirection: PanelPageDirection = .forward

    let onSelect: (ClipboardItem) -> Void
    let onDismiss: () -> Void

    private struct FilterSignature: Equatable {
        let itemCount: Int
        let firstItemId: UUID?
        let search: String
        let showOnlyImages: Bool
        let showOnlyText: Bool
        let selectedGroupId: UUID?
    }

    private var filterSignature: FilterSignature {
        FilterSignature(
            itemCount: items.count,
            firstItemId: items.first?.id,
            search: search,
            showOnlyImages: showOnlyImages,
            showOnlyText: showOnlyText,
            selectedGroupId: selectedGroup?.id
        )
    }

    private var filtered: [ClipboardItem] { filteredItems }

    private var shortcutRange: Range<Int> {
        guard isCommandPressed else { return 0..<0 }
        let lowerBound = shortcutBaseIndexState
        let upperBound = min(filtered.count, shortcutBaseIndexState + 9)
        return lowerBound..<upperBound
    }

    private var pageRequest: PanelPageRequest? {
        guard pageRequestID > 0 else { return nil }
        return PanelPageRequest(id: pageRequestID, direction: pageRequestDirection)
    }

    private var collectionItems: [PanelClipSnapshot] {
        filtered.enumerated().map { index, item in
            PanelClipSnapshot(
                item: item,
                shortcutIndex: shortcutRange.contains(index) ? index - shortcutBaseIndexState : nil
            )
        }
    }

    private var groupSnapshots: [PanelGroupSnapshot] {
        groups.map { PanelGroupSnapshot(id: $0.id, name: $0.name) }
    }

    private func triggerPage(_ direction: PanelPageDirection) {
        pageRequestDirection = direction
        pageRequestID += 1
    }

    private func item(for id: UUID) -> ClipboardItem? {
        items.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                isAddingGroup = true
                                newGroupName = ""
                            }
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(0.1))
                                isNewGroupFocused = true
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                        .help("添加分组")

                        Button {
                            if let group = selectedGroup {
                                if (group.items?.isEmpty ?? true) {
                                    modelContext.delete(group)
                                    selectedGroup = nil
                                    try? modelContext.save()
                                } else {
                                    groupToDelete = group
                                    showDeleteAlert = true
                                }
                            }
                        } label: {
                            Image(systemName: "minus")
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedGroup == nil)
                        .opacity(selectedGroup == nil ? 0.3 : 1.0)
                        .help("删除当前分组")
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            GroupButton(title: "全部", isSelected: selectedGroup == nil) {
                                selectedGroup = nil
                            }

                            ForEach(groups) { group in
                                GroupButton(title: group.name, isSelected: selectedGroup == group) {
                                    selectedGroup = group
                                }
                            }

                            if isAddingGroup {
                                TextField("新分组", text: $newGroupName)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.1))
                                    .cornerRadius(6)
                                    .frame(width: 80)
                                    .focused($isNewGroupFocused)
                                    .onSubmit {
                                        if !newGroupName.trimmingCharacters(in: .whitespaces).isEmpty {
                                            let group = ClipGroup(name: newGroupName)
                                            modelContext.insert(group)
                                            selectedGroup = group
                                            try? modelContext.save()
                                        }
                                        isAddingGroup = false
                                    }
                                    .onChange(of: isNewGroupFocused) { _, focused in
                                        if !focused {
                                            isAddingGroup = false
                                        }
                                    }
                            }
                        }
                    }
                    .frame(maxWidth: 250, alignment: .leading)

                    Divider().frame(height: 16)

                    Button {
                        showOnlyImages.toggle()
                        if showOnlyImages {
                            showOnlyText = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showOnlyImages ? "photo.fill" : "photo")
                            if showOnlyImages {
                                Text("仅图片")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(showOnlyImages ? Color.accentColor : Color.primary.opacity(0.05))
                        .foregroundColor(showOnlyImages ? .white : .primary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("仅显示图片内容")

                    Button {
                        showOnlyText.toggle()
                        if showOnlyText {
                            showOnlyImages = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showOnlyText ? "doc.text.fill" : "doc.text")
                            if showOnlyText {
                                Text("仅文本")
                                    .font(.system(size: 11, weight: .medium))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(showOnlyText ? Color.accentColor : Color.primary.opacity(0.05))
                        .foregroundColor(showOnlyText ? .white : .primary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("仅显示文本内容")

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                        TextField("搜索剪贴板历史...", text: $search)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .focused($isSearchFocused)
                        if !search.isEmpty {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    search = ""
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    Text("Ctrl+V 关闭")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .opacity(0.5)

                    Menu {
                        SettingsLink {
                            Text("设置...")
                        }
                        .keyboardShortcut(",", modifiers: .command)

                        Divider()

                        Button("退出 CoffeePaste") {
                            NSApplication.shared.terminate(nil)
                        }
                        .keyboardShortcut("q", modifiers: .command)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider().opacity(0.3)

                Group {
                    if filtered.isEmpty {
                        HStack {
                            Spacer()
                            Label(search.isEmpty ? "还没有复制记录" : "没有匹配内容", systemImage: "tray")
                                .foregroundColor(.secondary)
                                .font(.system(size: 13))
                            Spacer()
                        }
                    } else {
                        PanelCollectionView(
                            items: collectionItems,
                            groups: groupSnapshots,
                            pageRequest: pageRequest,
                            onVisibleIndexChange: { newIndex in
                                let clampedIndex = max(0, min(newIndex, max(0, filtered.count - 1)))
                                visibleBaseIndexState = clampedIndex
                                if isCommandPressed {
                                    shortcutBaseIndexState = clampedIndex
                                }
                            },
                            onSelect: { id in
                                if let item = item(for: id) {
                                    onSelect(item)
                                }
                            },
                            onDelete: { id in
                                if let item = item(for: id) {
                                    modelContext.delete(item)
                                    try? modelContext.save()
                                }
                            },
                            onAssignGroup: { itemID, groupID in
                                guard let item = item(for: itemID) else { return }
                                item.group = groups.first(where: { $0.id == groupID })
                                try? modelContext.save()
                            }
                        )
                    }
                }
                .frame(height: 154)
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            Group {
                ForEach(0..<9, id: \.self) { index in
                    Button("") {
                        let targetIndex = visibleBaseIndexState + index
                        if targetIndex < filtered.count {
                            onSelect(filtered[targetIndex])
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .opacity(0)
                }
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: .showPanel)) { _ in
            search = ""
            Task { @MainActor in
                isSearchFocused = false
                try? await Task.sleep(for: .seconds(0.1))
                isSearchFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandModifierChanged)) { notification in
            let isPressed = (notification.object as? Bool) ?? false
            isCommandPressed = isPressed
            if isPressed {
                shortcutBaseIndexState = visibleBaseIndexState
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelPageBackward)) { _ in
            triggerPage(.backward)
        }
        .onReceive(NotificationCenter.default.publisher(for: .panelPageForward)) { _ in
            triggerPage(.forward)
        }
        .task(id: filterSignature) { @MainActor in
            let sourceItems = selectedGroup == nil ? Array(items.prefix(maxDisplayCount)) : items
            filteredItems = sourceItems.filter { item in
                let matchesSearch = search.isEmpty || item.content.localizedCaseInsensitiveContains(search)
                let matchesImageFilter = !showOnlyImages || item.type == "image"
                let matchesTextFilter = !showOnlyText || item.type == "text"
                let matchesGroup = selectedGroup == nil || item.group == selectedGroup
                return matchesSearch && matchesImageFilter && matchesTextFilter && matchesGroup
            }

            if visibleBaseIndexState >= filteredItems.count {
                visibleBaseIndexState = max(0, filteredItems.count - 1)
            }
            if shortcutBaseIndexState >= filteredItems.count {
                shortcutBaseIndexState = max(0, filteredItems.count - 1)
            }
        }
        .alert("删除分组", isPresented: $showDeleteAlert, presenting: groupToDelete) { group in
            Button("取消", role: .cancel) {
                groupToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let groupToDelete {
                    modelContext.delete(groupToDelete)
                    if selectedGroup == groupToDelete {
                        selectedGroup = nil
                    }
                    try? modelContext.save()
                }
                groupToDelete = nil
            }
        } message: { group in
            Text("分组 \"\(group.name)\" 中还有记录，确定要删除吗？（记录不会被删除，仅移除分组信息）")
        }
    }
}
