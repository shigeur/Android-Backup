import Foundation

@MainActor
class FileOperationService: ObservableObject {
    static let shared = FileOperationService()
    
    @Published var isOperating = false
    @Published var operationProgress: Double = 0.0
    @Published var operationDescription: String = ""
    @Published var error: String?
    
    private init() {}
    
    func deleteMacFiles(urls: [URL]) async {
        isOperating = true
        operationProgress = 0.0
        error = nil
        let total = urls.count
        var count = 0
        
        for url in urls {
            do {
                operationDescription = "Trashing \(url.lastPathComponent)"
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            } catch {
                print("Failed to trash \(url): \(error)")
                self.error = "Failed to trash some items."
            }
            count += 1
            operationProgress = Double(count) / Double(total)
        }
        
        isOperating = false
        // Invalidate parents
        let parents = Set(urls.map { $0.deletingLastPathComponent().path })
        for parent in parents {
            await DirectoryCache.shared.invalidateMacCache(for: parent)
        }
    }
    
    func deleteAndroidFiles(device: AndroidDevice, paths: [String]) async {
        isOperating = true
        operationProgress = 0.0
        error = nil
        let total = paths.count
        var count = 0
        
        for path in paths {
            do {
                operationDescription = "Deleting \(URL(fileURLWithPath: path).lastPathComponent)"
                // Indeterminate on ADB level, but we loop through paths so there is some progress
                let cmd = ["-s", device.serial, "shell", "rm", "-r", "'\(path)'"]
                _ = try await ADBManager.shared.run(cmd)
            } catch {
                print("Failed to delete \(path): \(error)")
                self.error = "Failed to delete some items."
            }
            count += 1
            operationProgress = Double(count) / Double(total)
        }
        
        isOperating = false
        
        let parents = Set(paths.map { ($0 as NSString).deletingLastPathComponent })
        for parent in parents {
            await DirectoryCache.shared.invalidateAndroidCache(for: parent)
        }
    }
    
    func renameMacFile(url: URL, newName: String) async {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
            await DirectoryCache.shared.invalidateMacCache(for: url.deletingLastPathComponent().path)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func renameAndroidFile(device: AndroidDevice, path: String, newName: String) async {
        let parentDir = (path as NSString).deletingLastPathComponent
        let newPath = (parentDir as NSString).appendingPathComponent(newName)
        do {
            let cmd = ["-s", device.serial, "shell", "mv", "'\(path)'", "'\(newPath)'"]
            _ = try await ADBManager.shared.run(cmd)
            await DirectoryCache.shared.invalidateAndroidCache(for: parentDir)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func newMacFolder(parentURL: URL, name: String) async {
        let newURL = parentURL.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
            await DirectoryCache.shared.invalidateMacCache(for: parentURL.path)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func newAndroidFolder(device: AndroidDevice, parentPath: String, name: String) async {
        let newPath = (parentPath as NSString).appendingPathComponent(name)
        do {
            let cmd = ["-s", device.serial, "shell", "mkdir", "'\(newPath)'"]
            _ = try await ADBManager.shared.run(cmd)
            await DirectoryCache.shared.invalidateAndroidCache(for: parentPath)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func duplicateMacFiles(urls: [URL]) async {
        isOperating = true
        let total = urls.count
        var count = 0
        for url in urls {
            let ext = url.pathExtension
            let nameWithoutExt = url.deletingPathExtension().lastPathComponent
            let newName = "\(nameWithoutExt) copy" + (ext.isEmpty ? "" : ".\(ext)")
            let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
            do {
                try FileManager.default.copyItem(at: url, to: newURL)
            } catch {
                print("Failed to duplicate \(url): \(error)")
            }
            count += 1
            operationProgress = Double(count) / Double(total)
        }
        isOperating = false
        let parents = Set(urls.map { $0.deletingLastPathComponent().path })
        for parent in parents {
            await DirectoryCache.shared.invalidateMacCache(for: parent)
        }
    }
}
