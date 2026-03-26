import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]
    @State private var search = ""

    var filtered: [ClipboardItem] {
        search.isEmpty ? items : items.filter { $0.content.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏
            HStack {
                Image(systemName: "cup.and.saucer.fill").foregroundColor(.brown)
                Text("CoffeePaste").font(.headline)
                Spacer()
                Text("\(items.count) 条").font(.caption).foregroundColor(.secondary)
                Button { items.forEach { modelContext.delete($0) }; try? modelContext.save() } label: {
                    Image(systemName: "trash").foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)

            Divider()

            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("搜索剪贴板...", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // 列表
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clipboard").font(.largeTitle).foregroundColor(.secondary)
                    Text(search.isEmpty ? "还没有复制任何内容" : "没有匹配结果").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { item in
                    ItemRow(item: item) {
                        modelContext.delete(item)
                        try? modelContext.save()
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 360, height: 480)
    }
}

struct ItemRow: View {
    let item: ClipboardItem
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.content)
                    .lineLimit(2)
                    .font(.system(size: 13))
            }
            Spacer()
            if hovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark").font(.caption).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .background(hovered ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(4)
        .onTapGesture {
            // 写回剪贴板
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.content, forType: .string)
        }
    }
}
