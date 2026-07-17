import Foundation
import AppKit

protocol FileBrowserItem: Identifiable, Hashable {
    var id: String { get }
    var name: String { get }
    var isDirectory: Bool { get }
    var size: Int64 { get }
    var modifiedDate: Date { get }
    var iconImage: NSImage? { get }
    var pasteboardWriter: NSPasteboardWriting { get }
}
