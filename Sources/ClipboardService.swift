import Foundation
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
    let sourceDeviceSerial: String? // Needed if Android is the source
}

@MainActor
class ClipboardService: ObservableObject {
    static let shared = ClipboardService()
    
    @Published var currentItem: ClipboardItem?
    
    private init() {}
    
    func copy(paths: [String], platform: FilePlatform, deviceSerial: String? = nil) {
        currentItem = ClipboardItem(action: .copy, platform: platform, paths: paths, sourceDeviceSerial: deviceSerial)
    }
    
    func cut(paths: [String], platform: FilePlatform, deviceSerial: String? = nil) {
        currentItem = ClipboardItem(action: .cut, platform: platform, paths: paths, sourceDeviceSerial: deviceSerial)
    }
    
    func clear() {
        currentItem = nil
    }
    
    var hasContent: Bool {
        return currentItem != nil && !(currentItem?.paths.isEmpty ?? true)
    }
}
