# AGENTS.md — macOS App Development Guide

> 本文件是面向 AI 编码助手（Cursor、Claude Code、Copilot 等）的项目规范。
> 所有代码生成、重构、审查均须遵守以下规则。

---

## 🖥️ 项目定位

| 属性 | 值 |
|------|-----|
| 平台 | macOS 15 Sequoia+（最低部署目标） |
| 架构 | **arm64 (Apple Silicon 专用)**，不再支持 x86_64 |
| 语言 | Swift 6（开启完全并发检查） |
| UI 框架 | SwiftUI（优先）/ AppKit（允许用于窗口底层管理、全局事件监听，以及**性能关键滚动列表**如 `NSCollectionView`） |
| 数据层 | SwiftData |
| 包管理 | Swift Package Manager |

---

## ⚡ 技术栈要求

### Swift 6 & 并发
- **强制开启严格并发检查** (`Complete`)
- 禁止使用 `DispatchQueue.main`，统一使用 `@MainActor` 或 `MainActor.run`
- 数据监听使用 `AsyncStream`
- 所有 IO 操作（如文件读写）必须放在非主线程的 `actor` 中

### SwiftUI 规范
- **Observation 框架优先**：使用 `@Observable` 宏
- 视图逻辑分离：复杂 View 必须提取子 View 或配套 ViewModel，单个文件控制在 **200 行**内
  - 例外：为性能关键 AppKit bridge（如 `NSCollectionView` + `NSViewRepresentable`）可适度超过 200 行，但必须保持职责单一、可复用、无业务逻辑堆叠
- 状态管理：优先使用 `@State` 和 `@Bindable`，减少 `@EnvironmentObject` 的滥用

---

## 🎨 UI / 视觉效果 (2026 风格)

> 目标：**原生 macOS 质感 × 极致流畅动画**

### 核心视觉 API

| 效果 | API |
|------|-----|
| 动态背景 | `MeshGradient` (macOS 15) / `.background(.ultraThinMaterial)` |
| 滚动交互 | `.onScrollGeometryChange` (macOS 15) |
| 动画曲线 | `.animation(.spring(response: 0.3, dampingFraction: 0.7))` |
| 符号动画 | `.symbolEffect(.bounce)` |
| 着色器 | `.colorEffect()` (仅用于高性能视觉反馈) |

### 动画黄金法则
1. **状态变化必带动画**：禁止裸 `state = newValue`
2. **渐进式加载**：耗时资源加载时使用 `redacted(reason: .placeholder)`
3. **触感反馈**：卡片交互应有微小的缩放或位移反馈 (如 `1.02` 缩放)

---

## 🏗️ 项目结构

```
CoffeePaste/
├── CoffeePaste/          # 目前为平铺结构（逐步演进到模块化目录）
│  ├── AppDelegate.swift
│  ├── CoffeePasteApp.swift
│  ├── PanelView.swift
│  ├── PanelCollectionView.swift   # 性能关键列表内核（NSCollectionView）
│  ├── ClipboardMonitor.swift
│  ├── ClipboardItem.swift
│  ├── SettingsView.swift
│  ├── ContentView.swift
│  └── Assets.xcassets
└── Tests/                # Swift Testing（当前可能尚未完善）
```

---

## 🤖 AI 助手工作规则

当 AI 在此项目中生成或修改代码时，**必须**：

1. **2026 纯血 arm64**：不生成任何向后兼容 (Backport) 代码，不考虑 Intel 架构优化
2. **强制动画**：所有 UI 状态变化都需配套动画
3. **Actor 安全**：所有并发代码必须通过 Swift 6 检查，不产生任何 Data Race
4. **拒绝庞大 View**：如果 View 逻辑过重，必须主动建议并执行重构
5. **Swift Testing 优先**：新增业务逻辑时，同步生成对应的 `@Test`
6. **Shell 脚本同步**：修改编译路径或架构时，同步更新 `build.sh` 和 `install.sh`

### Shell 脚本约定
- `build.sh` 只负责编译产物，**不应修改** `install.sh`（避免“构建脚本篡改安装脚本”造成不可预期行为）
- `install.sh` 使用 `ditto` 复制 `.app`（比 `cp -r` 更稳，避免丢失 `Contents/MacOS`）
