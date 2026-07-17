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
                        .onDrag { NSItemProvider(object: item.name as NSString) }
                }
            }
            .background(TableDoubleClickHandler {
                doubleClickLog = "Double clicked at \(Date())"
            })
        }
        .frame(width: 400, height: 400)
    }
}

struct TableDoubleClickHandler: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = DoubleClickCatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? DoubleClickCatcherView {
            view.action = action
        }
    }
}

class DoubleClickCatcherView: NSView {
    var action: (() -> Void)?
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        
        DispatchQueue.main.async {
            var parent: NSView? = self.superview
            while parent != nil {
                if let tableView = parent as? NSTableView {
                    tableView.doubleAction = #selector(self.handleDoubleClick)
                    tableView.target = self
                    break
                }
                parent = parent?.superview
            }
        }
    }
    
    @objc func handleDoubleClick() {
        action?()
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
