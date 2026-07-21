import SwiftUI
import AppKit

struct WindowStateTracker: NSViewRepresentable {
    let autosaveName: String
    let isConnected: Bool
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            window.setFrameAutosaveName(isConnected ? autosaveName : "")
        } else {
            DispatchQueue.main.async {
                nsView.window?.setFrameAutosaveName(isConnected ? autosaveName : "")
            }
        }
    }
}

extension View {
    func windowAutosaveName(_ name: String, isConnected: Bool = true) -> some View {
        self.background(WindowStateTracker(autosaveName: name, isConnected: isConnected))
    }
}
