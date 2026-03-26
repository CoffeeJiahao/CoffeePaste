import SwiftUI
import SwiftData
struct PanelView: View {
    @Query(sort: \ClipboardItem.createdAt, order: .reverse) private var items: [ClipboardItem]
    @Query(sort: \ClipGroup.createdAt) private var groups: [ClipGroup]
    @Environment(\.modelContext) private var modelContext
    @State private var search = ""
    @State private var showOnlyImages = false
    @FocusState private var isSearchFocused: Bool
    
    // 分组状态
    @State private var selectedGroup: ClipGroup? = nil
    @State private var isAddingGroup = false
    @State private var newGroupName = ""
    @FocusState private var isNewGroupFocused: Bool
    @State private var groupToDelete: ClipGroup? = nil
    @State private var showDeleteAlert = false

    let onSelect: (ClipboardItem) -> Void
    let onDismiss: () -> Void

    var filtered: [ClipboardItem] {
        items.filter { item in
            let matchesSearch = search.isEmpty || item.content.localizedCaseInsensitiveContains(search)
            let matchesType = !showOnlyImages || item.type == "image"
            let matchesGroup = selectedGroup == nil || item.group == selectedGroup
            return matchesSearch && matchesType && matchesGroup
        }
    }

    var body: some View {
        ZStack {
            Color.clear
                .background(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // 搜索栏
                HStack(spacing: 12) {
                    // 分组操作按钮
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
                    
                    // 分组列表
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
                            Button { 
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    search = "" 
                                }
                            } label: {
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
                                ClipCard(item: item, index: index, groups: groups) {
                                    onSelect(item)
                                } onDelete: {
                                    modelContext.delete(item)
                                    try? modelContext.save()
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.viewAligned) // macOS 14+ 优化滚动停靠
                    .scrollIndicators(.hidden)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: .showPanel)) { _ in
            search = "" // 每次打开清空搜索

            // 确保窗口是 KeyWindow 之后再聚焦
            Task { @MainActor in
                isSearchFocused = false
                try? await Task.sleep(for: .seconds(0.1))
                isSearchFocused = true
            }
        }
        .alert("删除分组", isPresented: $showDeleteAlert, presenting: groupToDelete) { group in
            Button("取消", role: .cancel) {
                groupToDelete = nil
            }
            Button("删除", role: .destructive) {
                if let g = groupToDelete {
                    modelContext.delete(g)
                    if selectedGroup == g {
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
