import SwiftUI
import SwiftData
struct PanelView: View {
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]
    @Environment(\.modelContext) private var modelContext
    @State private var search = ""
    @State private var offsetY: CGFloat = 220   // 初始在屏幕外
    @State private var showOnlyImages = false
    @FocusState private var isSearchFocused: Bool

    let onSelect: (ClipboardItem) -> Void
    let onDismiss: () -> Void

    var filtered: [ClipboardItem] {
        items.filter { item in
            let matchesSearch = search.isEmpty || item.content.localizedCaseInsensitiveContains(search)
            let matchesType = !showOnlyImages || item.type == "image"
            return matchesSearch && matchesType
        }
    }

    var body: some View {
        ZStack {
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)

            VStack(spacing: 0) {
                // 搜索栏
                HStack(spacing: 12) {
                    // 仅看图片按钮
                    Button {
                        showOnlyImages.toggle()
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

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                        TextField("搜索剪贴板历史...", text: $search)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .focused($isSearchFocused)
                        if !search.isEmpty {
                            Button { search = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }.buttonStyle(.plain)
                        }
                    }
                    
                    Spacer()
                    Text("Ctrl+V 关闭").font(.caption2).foregroundColor(.secondary).opacity(0.5)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider().opacity(0.3)

                // 卡片横向列表
                if filtered.isEmpty {
                    HStack {
                        Spacer()
                        Label(search.isEmpty ? "还没有复制记录" : "没有匹配内容", systemImage: "tray")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                        Spacer()
                    }
                    .padding(.vertical, 30)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                                ClipCard(item: item, index: index) {
                                    onSelect(item)
                                } onDelete: {
                                    modelContext.delete(item)
                                    try? modelContext.save()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .offset(y: offsetY)
        // 丝滑弹簧动画
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: offsetY)
        .onReceive(NotificationCenter.default.publisher(for: .showPanel)) { _ in
            offsetY = 0
            isSearchFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .hidePanel)) { _ in
            offsetY = 220
        }
    }
}

// MARK: - 单张卡片
struct ClipCard: View {
    let item: ClipboardItem
    let index: Int
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 内容预览
            ZStack(alignment: .topTrailing) {
                if item.type == "image", let data = item.imageData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.05))
                        .cornerRadius(6)
                } else {
                    Text(item.content)
                        .font(.system(size: 12))
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundColor(.primary)
                }
                
                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .foregroundColor(.accentColor)
                        .cornerRadius(4)
                        .opacity(0.8)
                }
            }

            Spacer(minLength: 0)

            // 底部时间 + 删除
            HStack {
                Text(item.createdAt, style: .relative)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                if hovered {
                    Button(action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
        }
        .padding(12)
        .frame(width: 160, height: 130)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hovered
                      ? Color.accentColor.opacity(0.18)
                      : Color(NSColor.windowBackgroundColor).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(hovered ? Color.accentColor.opacity(0.6) : Color.white.opacity(0.08),
                        lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
        .scaleEffect(hovered ? 1.04 : 1.0)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: hovered)
        .onHover { hovered = $0 }
        .onTapGesture { onTap() }
        .background(
            Group {
                if index < 9 {
                    Button("") {
                        onTap()
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .opacity(0)
                }
            }
        )
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
