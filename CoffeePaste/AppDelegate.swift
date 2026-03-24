
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
                    print("✅ HotKey 触发了！")
                    DispatchQueue.main.async {
                        if let panel = AppDelegate.shared?.panelWindow, panel.isVisible {
                            AppDelegate.shared?.hidePanel()
                        } else {
                            AppDelegate.shared?.showPanel()
                        }
                    }
                    return noErr
                },
                1, &eventType, nil, nil
            )
            print("🔥 InstallEventHandler 结果: \(handlerStatus == noErr ? "成功" : "失败 \(handlerStatus)")")
    }
    // 在 AppDelegate 加一个控制动画的属性
    // 通过 NotificationCenter 通知 PanelView

    func showPanel() {
        print("🚀 showPanel() 被调用了")
        
        previousApp = NSWorkspace.shared.frontmostApplication
        print("   当前前台应用: \(previousApp?.localizedName ?? "未知")")
        
        let screen = NSScreen.main ?? NSScreen.screens[0]
        print("   屏幕尺寸: \(screen.frame)")
        
        if panelWindow == nil {
            print("   首次创建 NSPanel...")
            
            let panelHeight: CGFloat = 220
            let panelRect = NSRect(x: screen.frame.minX,
                                   y: screen.frame.minY,
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
            panel.backgroundColor = .clear   // ← 临时改成半透明红，方便看
            panel.isOpaque = false
            panel.hasShadow = false                                        // ← 临时加阴影
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
            print("   NSPanel 创建完成")
        } else {
            print("   复用已存在的 panelWindow")
        }
        
        // 再次设置位置
        let panelRect = NSRect(x: screen.frame.minX,
                               y: screen.frame.minY,
                               width: screen.frame.width,
                               height: 220)
        panelWindow?.setFrame(panelRect, display: true)   // ← 改成 true，强制刷新
        print("   已设置 panel frame: \(panelRect)")
        
        panelWindow?.orderFront(nil)
        panelWindow?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        print("   orderFront + makeKey + activate 执行完毕")
        
        NotificationCenter.default.post(name: .showPanel, object: nil)
        print("   已发送 .showPanel 动画通知")
        
        // 额外检查
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("   0.1秒后面板是否可见: \(self.panelWindow?.isVisible ?? false)")
        }
    }

    func hidePanel() {
        guard let panel = panelWindow, panel.isVisible else { return }

        // 通知 SwiftUI 收起，动画结束后再隐藏窗口
        NotificationCenter.default.post(name: .hidePanel, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            panel.orderOut(nil)
        }
    }

    func pasteItem(_ item: ClipboardItem) {
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
