import SwiftUI

@main
struct AndroidBackupApp: App {
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar) // Modern macOS styling
        .commands {
            ApplicationMenu()
        }
        
        Window("About Android Backup", id: "about") {
            AboutWindow()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        
        Settings {
            SettingsView()
        }
        
        Window("Developer Diagnostics", id: "diagnostics") {
            DiagnosticPanelView()
        }
        .windowStyle(.hiddenTitleBar)
    }
}
