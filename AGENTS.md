# AGENTS.md — macOS App Development Guide

> 本文件是面向 AI 编码助手（Cursor、Claude Code、Copilot 等）的项目规范。
> 所有代码生成、重构、审查均须遵守以下规则。

---

## 🖥️ 项目定位

| 属性 | 值 |
|------|-----|
| 平台 | macOS 15 Sequoia+（最低部署目标） |
| 语言 | Swift 6（严格并发模式） |
| UI 框架 | SwiftUI（优先）/ AppKit（仅当 SwiftUI 无法覆盖时） |
| 数据层 | SwiftData |
| 图形加速 | Metal 3 / RealityKit 4 |
| 包管理 | Swift Package Manager（禁止 CocoaPods / Carthage） |

---

## ⚡ 技术栈要求

### Swift & 并发
- 使用 **Swift 6** 严格并发（`SWIFT_STRICT_CONCURRENCY = complete`）
- 所有异步操作用 `async/await` + `actor`，禁止 `DispatchQueue` 手动调度
- 数据流使用 `AsyncStream` / `AsyncThrowingStream`
- 禁止 `@objc` unless absolutely required for AppKit bridging

```swift
// ✅ 正确
@MainActor
final class ViewModel: ObservableObject { ... }

// ❌ 禁止
DispatchQueue.main.async { ... }
```

### SwiftUI 规范
- 使用 **Observation 框架**（`@Observable`）替代 `ObservableObject` + `@Published`
- 状态管理：`@State` → `@Bindable` → `Environment` 依次优先
- 使用 `SwiftData` 的 `@Query` 宏驱动列表视图
- 拆分原则：单个 View 文件不超过 **150 行**；超出则提取子 View 或 ViewModifier

```swift
// ✅ 正确 — Observation
@Observable
final class AppState {
    var selectedItem: Item?
}

// ❌ 旧写法
class AppState: ObservableObject {
    @Published var selectedItem: Item?
}
```

### SwiftData
- 所有 Model 用 `@Model` 宏标注
- 关系用 `@Relationship(deleteRule:)` 显式声明
- 查询用 `#Predicate` 宏，禁止字符串谓词
- 迁移使用 `VersionedSchema` + `MigrationPlan`

---

## 🎨 UI / 视觉效果规范

> 目标：**原生 macOS 质感 × 现代视觉震撼**

### 必须使用的效果

| 效果 | API |
|------|-----|
| 液态玻璃 / 毛玻璃 | `.glassBackgroundEffect()` (macOS 15) |
| 弹性动画 | `.animation(.spring(duration:bounce:))` |
| 符号动画 | `.symbolEffect(.bounce)` / `.symbolEffect(.variableColor)` |
| 窗口半透明 | `NSVisualEffectView` / `.windowBackground(.ultraThinMaterial)` |
| Metal 粒子 | 自定义 `MTKView` / RealityKit ECS |
| 着色器效果 | SwiftUI `.colorEffect()` / `.layerEffect()` |

### 动画黄金法则
1. **所有状态变化必须有动画**，禁止裸 `state = newValue`（除非性能关键路径）
2. 使用 `withAnimation(.spring(...))` 包裹状态变更
3. 列表插入/删除使用 `.transition(.asymmetric(...))`
4. 耗时操作（网络、磁盘）显示骨架屏（`redacted(reason: .placeholder)`）

```swift
// ✅ 流畅过渡
withAnimation(.spring(duration: 0.4, bounce: 0.25)) {
    isExpanded.toggle()
}

// ✅ SF Symbols 动画
Image(systemName: "star.fill")
    .symbolEffect(.bounce, value: isFavorited)
    .symbolRenderingMode(.multicolor)
```

### 颜色与主题
- 使用 **自适应颜色**（Asset Catalog Any/Dark），禁止硬编码 `Color(hex:)`
- 主题色通过 `Environment(\.colorScheme)` 响应深色模式
- 支持 **Color Scheme Override** per-window

### 排版
- 正文：`.body` / `.callout`；标题：`.largeTitle` 配合 `.fontWeight(.bold)`
- 使用 `AttributedString` 处理富文本，禁止 HTML 字符串
- 支持动态字体（`@ScaledMetric`）

---

## 🏗️ 项目结构

```
AppName/
├── App/
│   ├── AppNameApp.swift        # @main 入口
│   └── AppDelegate.swift       # AppKit 生命周期（最小化）
├── Features/                   # 按功能模块划分
│   ├── Home/
│   │   ├── HomeView.swift
│   │   ├── HomeViewModel.swift  # @Observable
│   │   └── HomeView+Subviews.swift
│   └── Settings/
├── Models/                     # SwiftData @Model
├── Services/                   # Actor-based 服务层
├── Metal/                      # .metal 着色器文件
├── Assets.xcassets
├── Localizable.xcstrings       # String Catalog（非 .strings）
└── Tests/
    ├── UnitTests/
    └── UITests/
```

---

## 🔧 代码规范

### 命名
- 类型：`UpperCamelCase`；变量/函数：`lowerCamelCase`
- View：后缀 `View`；ViewModel：后缀 `ViewModel`；Service：后缀 `Service`
- 私有属性前缀 `_` 仅用于存储属性backing计算属性

### 注释
- 公开 API 必须有 `/// DocComment`
- 复杂算法写 `// MARK: - 算法说明` + 行内注释
- 禁止无意义注释（如 `// 设置颜色` 对应 `.foregroundStyle(.red)`）

### 错误处理
- 所有抛出错误使用自定义 `enum AppError: LocalizedError`
- 用户可见错误通过 `.alert(error:)` 展示
- 禁止 `try!` / `fatalError` 在生产代码（测试除外）

### 测试
- 业务逻辑覆盖率目标 **≥ 80%**
- 使用 Swift Testing 框架（`@Test` / `#expect`），非 XCTest
- UI 测试使用 XCUITest，关键用户流程必须覆盖

---

## 🚀 性能规范

| 指标 | 目标 |
|------|------|
| 启动时间（冷启动） | < 400ms |
| 主线程帧率 | 稳定 60fps（ProMotion 120fps） |
| 内存峰值 | < 200MB（普通使用） |
| 能耗 | 通过 Instruments Energy Gauge 无红区 |

- 列表使用 `LazyVStack` / `List`，禁止 `VStack` 渲染大量数据
- 图片使用 `AsyncImage` 或 `ImageRenderer`，启用磁盘缓存
- Metal 计算使用 `MTLCommandBuffer` 批处理，减少 CPU→GPU 往返

---

## 📦 依赖管理

### 允许引入的第三方库（需 PR 审批）
- `swift-algorithms` — 集合算法
- `swift-log` — 结构化日志
- `Nuke` — 图片加载（如 AsyncImage 不满足需求时）

### 明确禁止
- Alamofire（用 `URLSession` async/await）
- SnapKit / Masonry（纯 AppKit 布局用 autoresizingMask 或约束）
- 任何 ObjC 运行时 hack

---

## 🤖 AI 助手工作规则

当 AI 在此项目中生成或修改代码时，**必须**：

1. **优先使用最新 API**：检查是否有 macOS 15 / Swift 6 的新写法，不要使用已废弃接口
2. **不生成向后兼容代码**：部署目标已锁定 macOS 15，无需 `if #available` 守卫
3. **强制动画**：任何 UI 状态变化都需配套动画，不允许跳变
4. **Actor 安全**：所有新增的并发代码必须通过 Swift 6 严格并发检查
5. **自动添加测试**：新增业务逻辑时，同时生成对应 `@Test` 单元测试
6. **拒绝 MVC**：禁止将业务逻辑写入 View，必须分离到 ViewModel 或 Service
7. **SwiftLint 兼容**：生成代码须通过项目 `.swiftlint.yml` 规则，行长度 ≤ 120

### 生成代码时的输出格式
- 给出完整文件内容（非片段），包含所有 `import`
- 在文件顶部注明：`// Generated with Swift 6 + macOS 15 target`
- 如有架构决策，在代码前用 `> 💡 决策说明:` 简述原因

---

## 📋 Git 提交规范

```
<type>(<scope>): <subject>

type: feat | fix | perf | refactor | style | test | docs | chore
scope: 模块名（home | settings | metal | data）

示例：
feat(home): add spring-animated card expansion
perf(metal): batch particle updates in compute shader
fix(data): resolve SwiftData migration crash on cold start
```

---

*最后更新：2026-03 | 维护人：项目负责人*
*本文件由 Claude 协助生成，如有修改请同步更新*