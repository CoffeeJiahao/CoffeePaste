import SwiftUI

@main
struct CoffeePasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
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
            Text("☕")
        }
        
        Settings { 
            SettingsView()
        }
    }
}
