
import Carbon
import AppKit
import SwiftUI
import SwiftData
import IOKit.hid

class CustomPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?
    var statusItem: NSStatusItem!
    var panelWindow: NSPanel?
    var monitor: ClipboardMonitor!
    var container: ModelContainer!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var isAnimating = false
    private var isPanelShowing: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self   // ← 新增这一行
        // 申请 Accessibility
        let axOptions: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        AXIsProcessTrustedWithOptions(axOptions)

        // 申请 Input Monitoring（触发系统弹窗）
        IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
        let trusted = AXIsProcessTrustedWithOptions(options)
        print("Accessibility trusted: \(trusted)")

        NSApp.setActivationPolicy(.accessory)
        container = try! ModelContainer(for: ClipboardItem.self)

        monitor = ClipboardMonitor(modelContext: ModelContext(container))
        monitor.start()

        setupHotkey()
    }
    
    func setupHotkey() {
        // Carbon HotKey 注册 Ctrl+V，不需要 Input Monitoring 权限
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4350_4153), id: 1) // "CPAS"
        let modifiers: UInt32 = UInt32(controlKey)  // Ctrl
        let keyV: UInt32 = 9                          // V 键

        let regStatus = RegisterEventHotKey(keyV, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        print("🔥 RegisterEventHotKey 结果: \(regStatus == noErr ? "成功" : "失败 \(regStatus)")")
        // 安装事件处理器
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, _, _ in
                    DispatchQueue.main.async {
                        AppDelegate.shared?.togglePanel()
                    }
                    return noErr
                },
                1, &eventType, nil, nil
            )
            print("🔥 InstallEventHandler 结果: \(handlerStatus == noErr ? "成功" : "失败 \(handlerStatus)")")
    }

    func togglePanel() {
        if isAnimating { 
            print("⏳ 正在动画中，忽略请求")
            return 
        }
        
        print("尝试切换面板... 当前状态: isPanelShowing=\(isPanelShowing)")
        if isPanelShowing {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        if isAnimating || isPanelShowing { return }
        isAnimating = true
        isPanelShowing = true // 状态先行：立即标记为正在显示
        
        print("🎬 执行 showPanel")
        previousApp = NSWorkspace.shared.frontmostApplication
        
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let panelHeight: CGFloat = 220
        
        if panelWindow == nil {
            let panelRect = NSRect(x: screen.frame.minX,
                                   y: screen.frame.minY - panelHeight,
                                   width: screen.frame.width,
                                   height: panelHeight)
            
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
            
            let view = PanelView(
                onSelect: { [weak self] item in self?.pasteItem(item) },
                onDismiss: { [weak self] in self?.hidePanel() }
            ).modelContainer(container)
            
            panel.contentView = NSHostingView(rootView: view)
            
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(panelResignedKey),
                name: NSWindow.didResignKeyNotification,
                object: panel
            )
            
            panelWindow = panel
        }
        
        guard let panel = panelWindow else { 
            isAnimating = false
            isPanelShowing = false
            return 
        }
        
        let finalFrame = NSRect(x: screen.frame.minX,
                               y: screen.frame.minY,
                               width: screen.frame.width,
                               height: panelHeight)
        let startFrame = NSRect(x: screen.frame.minX,
                               y: screen.frame.minY - panelHeight,
                               width: screen.frame.width,
                               height: panelHeight)
        
        if abs(panel.frame.origin.y - finalFrame.origin.y) > 1 {
            panel.setFrame(startFrame, display: true)
        }
        
        panel.orderFront(nil)
        panel.makeKey()
        NotificationCenter.default.post(name: .showPanel, object: nil)
        
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(finalFrame, display: true)
        }) {
            self.isAnimating = false
            print("✅ showPanel 动画完成")
        }
    }

    func hidePanel() {
        // 状态先行：立即检查并标记为不在显示
        guard let panel = panelWindow, isPanelShowing, !isAnimating else { return }
        isAnimating = true
        isPanelShowing = false
        
        print("🎬 执行 hidePanel")
        panel.makeFirstResponder(nil)
        
        let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let panelHeight: CGFloat = 220
        let hideFrame = NSRect(x: screen.frame.minX,
                              y: screen.frame.minY - panelHeight,
                              width: screen.frame.width,
                              height: panelHeight)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(hideFrame, display: true)
        }) {
            panel.orderOut(nil)
            panel.setFrame(hideFrame, display: false)
            self.isAnimating = false
            print("✅ hidePanel 动画完成")
        }
    }

    func pasteItem(_ item: ClipboardItem) {
        // 粘贴时直接调用 hidePanel，它会处理状态
        hidePanel()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.previousApp?.activate(options: [])

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                let pb = NSPasteboard.general
                pb.clearContents()
                
                if item.type == "image", let data = item.imageData {
                    pb.setData(data, forType: .tiff)
                } else {
                    pb.setString(item.content, forType: .string)
                }

                // 对于图片，我们模拟 Cmd+V 粘贴
                if item.type == "image" {
                    let source = CGEventSource(stateID: .combinedSessionState)
                    let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
                    vDown?.flags = .maskCommand
                    let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
                    vUp?.flags = .maskCommand
                    
                    vDown?.post(tap: .cghidEventTap)
                    vUp?.post(tap: .cghidEventTap)
                } else {
                    // 对于文本，继续使用更稳定的 AX API
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


    @objc func panelResignedKey() {
        hidePanel()
    }
}
