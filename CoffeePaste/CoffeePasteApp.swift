import SwiftUI

@main
struct CoffeePasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            Button("显示剪贴板") {
                delegate.togglePanel()
            }
            .keyboardShortcut("v", modifiers: .command)
            
            Divider()
            
            SettingsLink {
                Text("设置...")
            }
            .keyboardShortcut(",", modifiers: .command)
            
            Divider()
            
            Button("退出 CoffeePaste") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            Image("MenuBarIcon")
        }
        
        Settings { 
            SettingsView()
        }
    }
}
