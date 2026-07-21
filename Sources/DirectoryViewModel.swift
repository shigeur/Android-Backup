import Foundation
import SwiftUI

@MainActor
class DirectoryViewModel: ObservableObject {
    @AppStorage("LastAndroidPath") private var lastAndroidPath: String = "/sdcard"
    @Published var currentPath: String = "/sdcard"
    @Published var files: [ADBFile] = []
    @Published var selectedFileIDs: Set<String> = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    
    private let directoryService: DirectoryService
    
    init(device: AndroidDevice? = nil) {
        self.directoryService = DirectoryService(device: device)
        if device != nil {
            self.currentPath = self.lastAndroidPath
            loadDirectory(self.currentPath)
        }
    }
    
    func updateDevice(_ device: AndroidDevice?) {
        self.directoryService.device = device
        if device != nil {
            // Restore previous directory or default
            let pathToLoad = currentPath.isEmpty ? lastAndroidPath : currentPath
            loadDirectory(pathToLoad)
        } else {
            // Clear files if disconnected
            self.currentPath = ""
            self.files = []
            self.selectedFileIDs.removeAll()
            self.isLoading = false
            self.error = nil
        }
    }
    
    func loadDirectory(_ path: String) {
        self.currentPath = path
        self.lastAndroidPath = path
        self.error = nil
        
        Task {
            if let cachedFiles = await DirectoryCache.shared.getAndroidCache(for: path) {
                self.files = cachedFiles
                self.isLoading = false
            } else {
                self.isLoading = true
                self.files = []
            }
            self.selectedFileIDs.removeAll()
            
            do {
                let fetchedFiles = try await directoryService.listDirectory(path)
                
                if self.files != fetchedFiles {
                    self.files = fetchedFiles
                    await DirectoryCache.shared.setAndroidCache(for: path, files: fetchedFiles)
                }
                
                self.isLoading = false
                
                DebugLogger.shared.lastIsLoading = false
                DebugLogger.shared.lastViewModelRows = fetchedFiles.count
                DebugLogger.shared.lastError = "none"
                DebugLogger.shared.lastDirectory = path
                
                DiagnosticLogger.shared.log("Directory Loaded (Android): \(path)", category: .directory)
                
            } catch {
                if self.files.isEmpty {
                    self.error = error.localizedDescription
                }
                self.isLoading = false
                
                DebugLogger.shared.lastIsLoading = false
                DebugLogger.shared.lastError = error.localizedDescription
            }
        }
    }
    
    func navigateUp() {
        let upPath = URL(fileURLWithPath: currentPath).deletingLastPathComponent().path
        loadDirectory(upPath == "" ? "/" : upPath)
    }
    
    func reloadCurrentDirectory(selecting newFileID: String? = nil, fallbackIndex: Int? = nil) {
        let path = currentPath
        
        Task {
            TransferTrace.logDirectory(requested: true, path: path)
            let startTime = Date()
            TransferTrace.logDirectory(started: true, path: path)
            do {
                let fetchedFiles = try await directoryService.listDirectory(path)
                
                let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
                TransferTrace.logDirectory(finished: true, itemCount: fetchedFiles.count, durationMs: durationMs, path: path)
                
                if self.files != fetchedFiles {
                    self.files = fetchedFiles
                    await DirectoryCache.shared.setAndroidCache(for: path, files: fetchedFiles)
                }
                
                if let newFile = newFileID {
                    self.selectedFileIDs = [newFile]
                } else if let idx = fallbackIndex, !fetchedFiles.isEmpty {
                    let safeIdx = min(idx, fetchedFiles.count - 1)
                    self.selectedFileIDs = [fetchedFiles[safeIdx].id]
                } else if fallbackIndex != nil {
                    self.selectedFileIDs = []
                }
            } catch {
                print("[DirectoryViewModel] Failed to reload directory: \(error)")
            }
        }
    }
}
