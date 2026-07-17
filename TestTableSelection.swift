import SwiftUI
import AppKit

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
}

struct TestTableSelection: View {
    @State private var items = (1...10).map { FileItem(name: "File \($0)") }
    @State private var selection = Set<UUID>()
    @State private var doubleClickLog = ""
    
    var body: some View {
        VStack {
            Text("Selection: \(selection.count)")
            Text("Log: \(doubleClickLog)")
            
            Table(items, selection: $selection) {
                TableColumn("Name") { item in
                    Text(item.name)
                        .contentShape(Rectangle())
                        // Case A: Drag gesture
                        .onDrag { NSItemProvider(object: item.name as NSString) }
                        // Case B: Tap gesture
                        .onTapGesture(count: 2) {
                            doubleClickLog = "Double clicked \(item.name)"
                        }
                }
            }
        }
        .frame(width: 400, height: 400)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = TestTableSelection()
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
