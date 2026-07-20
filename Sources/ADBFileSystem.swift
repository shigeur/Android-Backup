import Foundation
import AppKit
import UniformTypeIdentifiers

enum FileType: String, Equatable {
    case file
    case directory
    case symlink
    case unknown
}

struct ADBFile: Identifiable, Equatable, Hashable {
    let id: String // Full remote path
    let name: String
    let path: String
    let type: FileType
    let size: Int64
    let modifiedDate: Date
    
    var isDirectory: Bool { type == .directory }
    var extensionStr: String {
        return isDirectory ? "" : URL(fileURLWithPath: name).pathExtension.lowercased()
    }
}

extension ADBFile: FileBrowserItem {
    var iconImage: NSImage? {
        if isDirectory {
            return NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil) ?? NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericFolderIcon)))
        }
        return NSWorkspace.shared.icon(forFileType: extensionStr.isEmpty ? "public.data" : extensionStr)
    }
    
    var pasteboardWriter: NSPasteboardWriting {
        let item = NSPasteboardItem()
        item.setString("android://\(path)", forType: .string)
        return item
    }
}

class DirectoryService {
    let device: AndroidDevice
    
    init(device: AndroidDevice) {
        self.device = device
    }
    
    func listDirectory(_ path: String) async throws -> [ADBFile] {
        // Robust command: append trailing slash so symlinked directories like /sdcard are traversed
        let targetPath = path.hasSuffix("/") ? path : path + "/"
        let safePath = "'" + targetPath.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let formatStr = "'%F||%s||%Y||%n'"
        let shellCmd = "find \(safePath) -maxdepth 1 -mindepth 1 -exec stat -c \(formatStr) {} \\;"
        
        let command = ["-s", device.serial, "shell", shellCmd]
        let result = try await ADBManager.shared.runDetailed(command)
        
        var files: [ADBFile] = []
        let lines = result.stdout.components(separatedBy: .newlines)
        
        for line in lines {
            if line.isEmpty || line.contains("No such file or directory") || line.contains("stat: ") || line.contains("find: ") { continue }
            
            let parts = line.components(separatedBy: "||")
            if parts.count >= 4 {
                let typeStr = parts[0]
                let sizeStr = parts[1]
                let mtimeStr = parts[2]
                let rawFullPath = parts[3...].joined(separator: "||") // In case filename has ||
                
                let type: FileType
                if typeStr.contains("directory") {
                    type = .directory
                } else if typeStr.contains("symbolic link") {
                    type = .symlink
                } else if typeStr.contains("regular file") || typeStr.contains("regular empty file") {
                    type = .file
                } else {
                    type = .unknown
                }
                
                let size = Int64(sizeStr) ?? 0
                let mtime = TimeInterval(mtimeStr) ?? 0
                
                let url = URL(fileURLWithPath: rawFullPath)
                let normalizedPath = url.path
                let name = url.lastPathComponent
                
                let file = ADBFile(
                    id: normalizedPath,
                    name: name,
                    path: normalizedPath,
                    type: type,
                    size: size,
                    modifiedDate: Date(timeIntervalSince1970: mtime)
                )
                files.append(file)
            }
        }
        
        let sorted = files.sorted {
            if $0.isDirectory && !$1.isDirectory { return true }
            if !$0.isDirectory && $1.isDirectory { return false }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        
        Task { @MainActor in
            DebugLogger.shared.lastFilesParsed = sorted.count
        }
        
        return sorted
    }
    
    func fileExists(_ path: String) async -> Bool {
        let command = ["-s", device.serial, "shell", "test", "-e", path, "&&", "echo", "1", "||", "echo", "0"]
        if let out = try? await ADBManager.shared.run(command), out == "1" {
            return true
        }
        return false
    }
}
