import Foundation
import AppKit
import Combine

enum ClipboardAction {
    case copy
    case cut
}

enum FilePlatform {
    case android
    case mac
}

struct ClipboardItem {
    let action: ClipboardAction
    let platform: FilePlatform
    let paths: [String]
    let sourceDeviceSerial: String?
    let timestamp: Date
}

@MainActor
class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var currentItem: ClipboardItem?
    private var lastPasteboardChangeCount: Int = 0
    
    private init() {}
    
    func copy(paths: [String], platform: FilePlatform, deviceSerial: String? = nil) {
        print("[DebugLogger] ClipboardManager received Copy: count=\(paths.count) platform=\(platform)")
        DiagnosticLogger.shared.log("Copied \(paths.count) items from \(platform)", category: .clipboard)
        currentItem = ClipboardItem(action: .copy, platform: platform, paths: paths, sourceDeviceSerial: deviceSerial, timestamp: Date())
        syncToPasteboard()
    }
    
    func cut(paths: [String], platform: FilePlatform, deviceSerial: String? = nil) {
        print("[DebugLogger] ClipboardManager received Cut: count=\(paths.count) platform=\(platform)")
        DiagnosticLogger.shared.log("Cut \(paths.count) items from \(platform)", category: .clipboard)
        currentItem = ClipboardItem(action: .cut, platform: platform, paths: paths, sourceDeviceSerial: deviceSerial, timestamp: Date())
        syncToPasteboard()
    }
    
    func clear() {
        currentItem = nil
        NSPasteboard.general.clearContents()
    }
    
    var hasContent: Bool {
        // Before returning hasContent, try to sync from pasteboard in case Finder copied something newer
        syncFromPasteboard()
        return currentItem != nil && !(currentItem?.paths.isEmpty ?? true)
    }
    
    func getLatestItem() -> ClipboardItem? {
        syncFromPasteboard()
        return currentItem
    }
    
    private func syncToPasteboard() {
        print("[DebugLogger] ClipboardManager syncToPasteboard started")
        guard let item = currentItem, !item.paths.isEmpty else {
            print("[DebugLogger] ClipboardManager syncToPasteboard: cleared NSPasteboard")
            NSPasteboard.general.clearContents()
            return
        }
        
        let pb = NSPasteboard.general
        pb.clearContents()
        
        if item.platform == .mac {
            // Write standard file URLs so Finder can paste them
            let urls = item.paths.map { URL(fileURLWithPath: $0) }
            pb.writeObjects(urls as [NSURL])
            print("[DebugLogger] ClipboardManager syncToPasteboard: wrote \(urls.count) mac URLs to NSPasteboard")
        } else {
            // Write as strings for internal use
            pb.writeObjects(item.paths as [NSString])
            print("[DebugLogger] ClipboardManager syncToPasteboard: wrote \(item.paths.count) android strings to NSPasteboard")
        }
        
        lastPasteboardChangeCount = pb.changeCount
    }
    
    private func syncFromPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastPasteboardChangeCount else { return }
        print("[DebugLogger] ClipboardManager syncFromPasteboard detected changeCount increase")
        lastPasteboardChangeCount = pb.changeCount
        
        // If pasteboard has file URLs, it's a Mac copy (e.g. from Finder)
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], !urls.isEmpty {
            print("[DebugLogger] ClipboardManager syncFromPasteboard: found \(urls.count) file URLs. Overwriting currentItem.")
            currentItem = ClipboardItem(action: .copy, platform: .mac, paths: urls.map { $0.path }, sourceDeviceSerial: nil, timestamp: Date())
        } else {
            // If it's something else not from our app, we should probably clear our internal clipboard
            // to avoid pasting stale files when the user actually copied text.
            print("[DebugLogger] ClipboardManager syncFromPasteboard: not file URLs. Clearing currentItem.")
            currentItem = nil
        }
    }
}

