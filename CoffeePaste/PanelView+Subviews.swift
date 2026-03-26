import SwiftUI
import SwiftData

@Observable
final class ShortcutState {
    static let shared = ShortcutState()
    var isCommandPressed = false
    private var monitor: Any?
    
    func startMonitoring() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            self.isCommandPressed = event.modifierFlags.contains(.command)
            return event
        }
    }
    
    func stopMonitoring() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
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
    let displayIndex: Int
    let groups: [ClipGroup]
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false
    @State private var decodedImage: Image? = nil
    @State private var isAnimating = false
    @Environment(\.modelContext) private var modelContext
    
    @State private var shortcutState = ShortcutState.shared

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
        .onTapGesture { onSelect() }
        .task(id: item.id) {
            await loadImageIfNeeded()
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
        .background(
            Group {
                if displayIndex >= 0 && displayIndex < 9 {
                    Button("") {
                        onSelect()
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(displayIndex + 1)")), modifiers: .command)
                    .opacity(0)
                }
            }
        )
    }

    private var topBar: some View {
        HStack {
            Text(formatTime(item.createdAt))
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.7))
            
            Spacer()
            
            if shortcutState.isCommandPressed && displayIndex >= 0 && displayIndex < 9 {
                Text("⌘\(displayIndex + 1)")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .foregroundColor(.accentColor)
                    .cornerRadius(4)
                    .opacity(0.8)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .animation(.easeInOut(duration: 0.1), value: shortcutState.isCommandPressed)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else {
            let daysAgo = calendar.dateComponents([.day], from: date, to: Date()).day ?? 0
            if daysAgo < 7 {
                formatter.dateFormat = "EEEE"
                formatter.locale = Locale(identifier: "zh_CN")
            } else {
                formatter.dateFormat = "MM/dd"
            }
        }
        return formatter.string(from: date)
    }

    @ViewBuilder
    private var contentPreview: some View {
        ZStack {
            if item.type == "image" {
                if let image = decodedImage {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity)
                } else {
                    // 使用纯 SwiftUI 的圆形加载动画，避免 native ProgressView 在 drawingGroup 下的渲染错误
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: 20, height: 20)
                        .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                        .onAppear {
                            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                                isAnimating = true
                            }
                        }
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
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 6)
    }

    @MainActor
    private func loadImageIfNeeded() async {
        guard item.type == "image" else { return }
        
        let dataToUse = item.thumbnailData ?? item.imageData
        guard let data = dataToUse else { return }
        
        let image: Image? = await Task.detached(priority: .userInitiated) {
            if let nsImage = NSImage(data: data) {
                return Image(nsImage: nsImage)
            }
            return nil as Image?
        }.value
        
        withAnimation(.easeOut(duration: 0.2)) {
            self.decodedImage = image
        }
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
