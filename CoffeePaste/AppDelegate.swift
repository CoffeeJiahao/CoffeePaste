import Carbon
import AppKit
import SwiftUI
import SwiftData
import IOKit.hid

// MARK: - 面板状态管理（全局 Observable）
@Observable
final class PanelState {
    var isVisible: Bool = false
    var searchText: String = ""
}

// MARK: - 自定义 NSPanel
class CustomPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - 带动画的容器视图
struct AnimatedPanelContainer: View {
    let panelState: PanelState
    let onSelect: (ClipboardItem) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.001)
                .onTapGesture { onDismiss() }
            
            PanelView(
                onSelect: onSelect,
                onDismiss: onDismiss
            )
            .frame(height: 220)
            .opacity(panelState.isVisible ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

// MARK: - AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var panelWindow: NSPanel?
    var monitor: ClipboardMonitor!
    var container: ModelContainer!
    
    private var previousApp: NSRunningApplication?
    private var panelState = PanelState()
    private let panelHeight: CGFloat = 220
    
    // 用 isPanelShowing 读 panelState 统一状态
    private var isPanelShowing: Bool {
        get { panelState.isVisible }
        set { panelState.isVisible = newValue }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(options)
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        
        NSApp.setActivationPolicy(.accessory)
        
        do {
            container = try ModelContainer(for: ClipboardItem.self, ClipGroup.self)
            monitor = ClipboardMonitor(modelContext: ModelContext(container))
            monitor.start()
        } catch {
            print("Failed to initialize SwiftData ModelContainer: \(error)")
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try? ModelContainer(for: ClipboardItem.self, ClipGroup.self, configurations: config)
            monitor = ClipboardMonitor(modelContext: ModelContext(container))
            monitor.start()
        }
        
        setupPanel()
        setupHotkey()
        ShortcutState.shared.startMonitoring()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }
    
    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window != panelWindow && window.styleMask.contains(.closable) {
            window.level = .floating
        }
    }
    
    // MARK: - 面板初始化（一次性，窗口位置固定不变）
    private func setupPanel() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        
        // 窗口固定在屏幕底部，全宽、高度 = panelHeight
        // 窗口本身永远不动！动画全部在 SwiftUI 层完成
        let panelRect = NSRect(
            x: screen.frame.minX,
            y: screen.frame.minY,
            width: screen.frame.width,
            height: panelHeight
        )
        
        let panel = CustomPanel(
            contentRect: panelRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .mainMenu
        panel.isFloatingPanel = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = false
        
        let rootView = AnimatedPanelContainer(
            panelState: panelState,
            onSelect: { [weak self] item in self?.pasteItem(item) },
            onDismiss: { [weak self] in self?.hidePanel() }
        )
        .modelContainer(container)
        
        panel.contentView = NSHostingView(rootView: rootView)
        
        // 监听失焦
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(panelResignedKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )
        
        panelWindow = panel
    }
    
    // MARK: - 快捷键
    func setupHotkey() {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4350_4153), id: 1)
        let modifiers: UInt32 = UInt32(controlKey)
        let keyV: UInt32 = 9
        
        RegisterEventHotKey(keyV, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                Task { @MainActor in
                    AppDelegate.shared?.togglePanel()
                }
                return noErr
            },
            1, &eventType, nil, nil
        )
    }
    
    // MARK: - Toggle / Show / Hide
    func togglePanel() {
        if isPanelShowing {
            hidePanel()
        } else {
            showPanel()
        }
    }
    
    func showPanel() {
        guard !isPanelShowing else { return }
        guard let panel = panelWindow else { return }
        
        previousApp = NSWorkspace.shared.frontmostApplication
        
        // 只有在屏幕变化或首次显示时才调整 Frame，减少 WindowServer 调用
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let rect = NSRect(x: screen.frame.minX, y: screen.frame.minY,
                          width: screen.frame.width, height: panelHeight)
        
        if panel.frame != rect {
            panel.setFrame(rect, display: false)
        }
        
        panel.orderFront(nil)
        panel.makeKey()
        
        // 强制 NSHostingView 成为第一响应者，否则 SwiftUI 内部 FocusState 无法响应
        if let contentView = panel.contentView {
            panel.makeFirstResponder(contentView)
        }
        
        // 触发 SwiftUI 动画
        isPanelShowing = true
        
        NotificationCenter.default.post(name: .showPanel, object: nil)
    }
    
    func hidePanel() {
        guard isPanelShowing else { return }
        
        panelWindow?.makeFirstResponder(nil)
        
        // 触发 SwiftUI 收起动画
        isPanelShowing = false
        
        // 动画结束后隐藏窗口（匹配动画时长 0.28s，多留 0.02s 冗余）
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.3))
            guard let self = self, !self.isPanelShowing else { return }
            self.panelWindow?.orderOut(nil)
        }
    }
    
    // MARK: - 粘贴
    func pasteItem(_ item: ClipboardItem) {
        // 1. 立即触发 SwiftUI 收起动画
        isPanelShowing = false
        
        // 2. 立即辞去 KeyWindow，让系统焦点开始自动返回前一个应用
        panelWindow?.resignKey()
        
        // 3. 立即激活前一个应用
        previousApp?.activate()
        
        // 4. 动画结束后隐藏窗口（常驻逻辑保持不变）
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.3))
            guard let self = self, !self.isPanelShowing else { return }
            self.panelWindow?.orderOut(nil)
        }
        
        // 5. 智能轮询焦点切换情况
        Task { @MainActor in
            let startTime = Date()
            while Date().timeIntervalSince(startTime) <= 0.2 {
                let systemWide = AXUIElementCreateSystemWide()
                var focusedElement: AnyObject?
                let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)
                
                var focusedPid: pid_t = 0
                if result == .success, let element = focusedElement {
                    AXUIElementGetPid(element as! AXUIElement, &focusedPid)
                }
                
                let myPid = ProcessInfo.processInfo.processIdentifier
                if (focusedPid != 0 && focusedPid != myPid) {
                    self.performActualPaste(item, targetElement: focusedElement)
                    return
                }
                try? await Task.sleep(for: .seconds(0.01))
            }
            // 超时后强制尝试粘贴
            self.performActualPaste(item, targetElement: nil)
        }
    }
    
    private func performActualPaste(_ item: ClipboardItem, targetElement: AnyObject?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        
        if item.type == "image", let data = item.imageData {
            pb.setData(data, forType: .tiff)
            self.simulateCmdV()
        } else {
            pb.setString(item.content, forType: .string)
            
            // 优先尝试使用 Accessibility API 直接注入文本，这是最快且不依赖 Cmd+V 的方式
            var success = false
            if let element = targetElement {
                let axElement = element as! AXUIElement
                let setResult = AXUIElementSetAttributeValue(
                    axElement,
                    kAXSelectedTextAttribute as CFString,
                    item.content as CFTypeRef
                )
                success = (setResult == .success)
            }
            
            // 如果 AX 注入失败（比如目标应用不支持），则降级使用模拟键盘 Cmd+V
            if !success {
                self.simulateCmdV()
            }
        }
    }
    
    private func simulateCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
    
    // MARK: - 失焦处理
    @objc func panelResignedKey() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.05))
            guard let self = self, self.isPanelShowing else { return }
            if self.panelWindow?.isKeyWindow == false {
                self.hidePanel()
            }
        }
    }
}
