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
            CommandGroup(replacing: .appInfo) {
                Button("About Android Backup") {
                    openWindow(id: "about")
                }
            }
        }
        
        Window("About Android Backup", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
