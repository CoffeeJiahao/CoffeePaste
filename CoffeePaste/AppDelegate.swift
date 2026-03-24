import Carbon
import AppKit
import SwiftUI
import SwiftData
import IOKit.hid

// MARK: - 面板状态管理（全局 Observable）
@Observable
class PanelState {
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
            // 半透明背景（可选，点击关闭）
            if panelState.isVisible {
                Color.black.opacity(0.001) // 几乎透明，仅用于捕获点击
                    .onTapGesture { onDismiss() }
                    .transition(.opacity)
            }
            
            // 主面板内容
            if panelState.isVisible {
                PanelView(
                    onSelect: onSelect,
                    onDismiss: onDismiss
                )
                .frame(height: 220)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom)
                            .combined(with: .opacity),
                        removal: .move(edge: .bottom)
                            .combined(with: .opacity)
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .animation(
            .spring(duration: 0.32, bounce: 0.08), // 带微弱弹性的弹簧动画
            value: panelState.isVisible
        )
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
        container = try! ModelContainer(for: ClipboardItem.self)
        monitor = ClipboardMonitor(modelContext: ModelContext(container))
        monitor.start()
        
        setupPanel()
        setupHotkey()
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
                DispatchQueue.main.async {
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
        
        // 确保窗口位置跟随当前主屏幕（多显示器支持）
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let rect = NSRect(x: screen.frame.minX, y: screen.frame.minY,
                          width: screen.frame.width, height: panelHeight)
        panel.setFrame(rect, display: false)
        
        // 先显示窗口（此时 SwiftUI 内容还没出来，因为 isVisible=false）
        panel.orderFront(nil)
        panel.makeKey()
        
        // 触发 SwiftUI 动画
        isPanelShowing = true
        
        NotificationCenter.default.post(name: .showPanel, object: nil)
    }
    
    func hidePanel() {
        guard isPanelShowing else { return }
        
        panelWindow?.makeFirstResponder(nil)
        
        // 触发 SwiftUI 收起动画
        isPanelShowing = false
        
        // 动画结束后隐藏窗口（匹配动画时长）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self, !self.isPanelShowing else { return }
            self.panelWindow?.orderOut(nil)
        }
    }
    
    // MARK: - 粘贴
    func pasteItem(_ item: ClipboardItem) {
        hidePanel()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.previousApp?.activate(options: [])
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let pb = NSPasteboard.general
                pb.clearContents()
                
                if item.type == "image", let data = item.imageData {
                    pb.setData(data, forType: .tiff)
                    self?.simulateCmdV()
                } else {
                    pb.setString(item.content, forType: .string)
                    
                    let systemWide = AXUIElementCreateSystemWide()
                    var focusedElement: AnyObject?
                    let result = AXUIElementCopyAttributeValue(
                        systemWide,
                        kAXFocusedUIElementAttribute as CFString,
                        &focusedElement
                    )
                    
                    if result == .success, let element = focusedElement {
                        let axElement = element as! AXUIElement
                        let setResult = AXUIElementSetAttributeValue(
                            axElement,
                            kAXSelectedTextAttribute as CFString,
                            item.content as CFTypeRef
                        )
                        if setResult != .success {
                            self?.simulateCmdV()
                        }
                    } else {
                        self?.simulateCmdV()
                    }
                }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self, self.isPanelShowing else { return }
            if self.panelWindow?.isKeyWindow == false {
                self.hidePanel()
            }
        }
    }
}
