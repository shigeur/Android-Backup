import SwiftUI

@main
struct AndroidBackupApp: App {
    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar) // Modern macOS styling
    }
}
