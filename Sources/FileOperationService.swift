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
                let cmd = ["-s", device.serial, "shell", "rm", "-r", path.adbEscaped]
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
            let cmd = ["-s", device.serial, "shell", "mv", path.adbEscaped, newPath.adbEscaped]
            _ = try await ADBManager.shared.run(cmd)
            await DirectoryCache.shared.invalidateAndroidCache(for: parentDir)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func newMacFolder(parentURL: URL, name: String) async throws -> URL {
        let startTime = Date()
        let newURL = parentURL.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
            await DirectoryCache.shared.invalidateMacCache(for: parentURL.path)
            
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            print("[DebugLogger] Folder Created: \(name) in \(parentURL.path) (Execution Time: \(durationMs)ms)")
            
            return newURL
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            print("[DebugLogger] Folder Creation Failed: \(name) in \(parentURL.path) (Execution Time: \(durationMs)ms) - Error: \(error.localizedDescription)")
            self.error = error.localizedDescription
            throw error
        }
    }
    
    func newAndroidFolder(device: AndroidDevice, parentPath: String, name: String) async throws -> String {
        let startTime = Date()
        let newPath = (parentPath as NSString).appendingPathComponent(name)
        do {
            let cmd = ["-s", device.serial, "shell", "mkdir", newPath.adbEscaped]
            _ = try await ADBManager.shared.run(cmd)
            await DirectoryCache.shared.invalidateAndroidCache(for: parentPath)
            
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            print("[DebugLogger] Android Folder Created: \(name) in \(parentPath) (Execution Time: \(durationMs)ms)")
            
            return newPath
        } catch let err as ADBError {
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            var exitCode = -1
            if case .executionFailed(let code, _) = err {
                exitCode = Int(code)
            }
            print("[DebugLogger] Android Folder Creation Failed: \(name) in \(parentPath) (Execution Time: \(durationMs)ms) - Exit Code: \(exitCode) - Error: \(err.localizedDescription)")
            self.error = err.localizedDescription
            throw err
        } catch {
            let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
            print("[DebugLogger] Android Folder Creation Failed: \(name) in \(parentPath) (Execution Time: \(durationMs)ms) - Error: \(error.localizedDescription)")
            self.error = error.localizedDescription
            throw error
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
    
    func copyMacFiles(urls: [URL], to destination: URL, sessionID: String? = nil, onProgress: TransferEngine.TransferProgressCallback? = nil) async {
        let sid = sessionID ?? UUID().uuidString
        isOperating = true
        let total = urls.count
        var count = 0
        onProgress?(TransferProgress(sessionID: sid, stage: .started, percentage: 0, filesCompleted: 0, totalFiles: total))
        for url in urls {
            let newURL = destination.appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: url, to: newURL)
                let pct = Double(count) / Double(total)
                onProgress?(TransferProgress(sessionID: sid, stage: .copying, percentage: pct, filesCompleted: count, totalFiles: total, currentFileName: url.lastPathComponent))
            } catch {
                let errStr = error.localizedDescription
                print("Failed to copy \(url) to \(newURL): \(errStr)")
                Task { @MainActor in
                    TransferTrace.logFailure(reason: "Mac Copy Error", function: "copyMacFiles", error: errStr)
                }
                self.error = errStr
                onProgress?(TransferProgress(sessionID: sid, stage: .failed, errorMessage: errStr))
                return
            }
            count += 1
            operationProgress = Double(count) / Double(total)
        }
        isOperating = false
        onProgress?(TransferProgress(sessionID: sid, stage: .refreshing))
        await DirectoryCache.shared.invalidateMacCache(for: destination.path)
        onProgress?(TransferProgress(sessionID: sid, stage: .completed, percentage: 1.0, filesCompleted: total, totalFiles: total))
    }
    
    func moveMacFiles(urls: [URL], to destination: URL, sessionID: String? = nil, onProgress: TransferEngine.TransferProgressCallback? = nil) async {
        let sid = sessionID ?? UUID().uuidString
        isOperating = true
        let total = urls.count
        var count = 0
        onProgress?(TransferProgress(sessionID: sid, stage: .started, percentage: 0, filesCompleted: 0, totalFiles: total))
        for url in urls {
            let newURL = destination.appendingPathComponent(url.lastPathComponent)
            do {
                try FileManager.default.moveItem(at: url, to: newURL)
                let pct = Double(count) / Double(total)
                onProgress?(TransferProgress(sessionID: sid, stage: .copying, percentage: pct, filesCompleted: count, totalFiles: total, currentFileName: url.lastPathComponent))
            } catch {
                let errStr = error.localizedDescription
                print("Failed to move \(url) to \(newURL): \(errStr)")
                Task { @MainActor in
                    TransferTrace.logFailure(reason: "Mac Move Error", function: "moveMacFiles", error: errStr)
                }
                self.error = errStr
                onProgress?(TransferProgress(sessionID: sid, stage: .failed, errorMessage: errStr))
                return
            }
            count += 1
            operationProgress = Double(count) / Double(total)
        }
        isOperating = false
        
        onProgress?(TransferProgress(sessionID: sid, stage: .refreshing))
        let oldParents = Set(urls.map { $0.deletingLastPathComponent().path })
        for parent in oldParents {
            await DirectoryCache.shared.invalidateMacCache(for: parent)
        }
        await DirectoryCache.shared.invalidateMacCache(for: destination.path)
        onProgress?(TransferProgress(sessionID: sid, stage: .completed, percentage: 1.0, filesCompleted: total, totalFiles: total))
    }
}
