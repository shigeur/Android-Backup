import Foundation
import Combine
import AppKit
import UniformTypeIdentifiers

enum LocalFileType: String {
    case file
    case directory
    case symlink
    case unknown
}

struct LocalFileItem: Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let url: URL
    let size: Int64
    let modifiedDate: Date
    let type: LocalFileType
    
    var isDirectory: Bool {
        return type == .directory
    }
    
    var extensionStr: String {
        return url.pathExtension.lowercased()
    }
}

extension LocalFileItem: FileBrowserItem {
    var iconImage: NSImage? {
        return NSWorkspace.shared.icon(forFile: path)
    }
    
    var pasteboardWriter: NSPasteboardWriting {
        return url as NSURL
    }
}

class LocalDirectoryService {
    static let shared = LocalDirectoryService()
    private let fileManager = FileManager.default
    
    func listDirectory(_ url: URL) throws -> [LocalFileItem] {
        let resourceKeys: [URLResourceKey] = [.nameKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        
        let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles])
        
        var files: [LocalFileItem] = []
        
        for itemURL in contents {
            let resourceValues = try itemURL.resourceValues(forKeys: Set(resourceKeys))
            
            let isDirectory = resourceValues.isDirectory ?? false
            let isSymlink = resourceValues.isSymbolicLink ?? false
            
            var type: LocalFileType = .file
            if isDirectory { type = .directory }
            else if isSymlink { type = .symlink }
            
            let size = Int64(resourceValues.fileSize ?? 0)
            let modifiedDate = resourceValues.contentModificationDate ?? Date()
            
            let file = LocalFileItem(
                id: itemURL.path,
                name: resourceValues.name ?? itemURL.lastPathComponent,
                path: itemURL.path,
                url: itemURL,
                size: size,
                modifiedDate: modifiedDate,
                type: type
            )
            files.append(file)
        }
        
        // Sort: Folders first, then alphabetically
        return files.sorted {
            if $0.isDirectory && !$1.isDirectory { return true }
            if !$0.isDirectory && $1.isDirectory { return false }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func loadRootDirectory(rootURL: inout URL, currentURL: inout URL, loadContents: (URL) -> Void) {
        let homeUrl = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? "/")
        rootURL = homeUrl
        currentURL = homeUrl
        loadContents(homeUrl)
    }
}
