import SwiftUI
import AppKit

struct SplitViewAutosaveTracker: NSViewRepresentable {
    let autosaveName: String
    let isConnected: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let splitView = findSplitView(in: nsView) {
            splitView.autosaveName = isConnected ? autosaveName : nil
        } else {
            DispatchQueue.main.async {
                if let splitView = findSplitView(in: nsView) {
                    splitView.autosaveName = isConnected ? autosaveName : nil
                }
            }
        }
    }
    
    private func findSplitView(in view: NSView) -> NSSplitView? {
        var current: NSView? = view
        while let s = current?.superview {
            if let split = s as? NSSplitView {
                return split
            }
            current = s
        }
        return nil
    }
}

extension View {
    func splitViewAutosave(_ name: String, isConnected: Bool = true) -> some View {
        self.background(SplitViewAutosaveTracker(autosaveName: name, isConnected: isConnected))
    }
}
