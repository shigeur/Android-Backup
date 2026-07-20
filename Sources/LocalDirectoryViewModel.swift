import Foundation
import Combine
import SwiftUI

@MainActor
class LocalDirectoryViewModel: ObservableObject {
    @Published var files: [LocalFileItem] = []
    @Published var currentURL: URL? = nil
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    @Published var selectedFileIDs: Set<String> = []
    
    private let directoryService = LocalDirectoryService.shared
    
    init() {
        let homeUrl = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? "/")
        loadDirectory(homeUrl)
    }
    
    func loadDirectory(_ url: URL) {
        self.currentURL = url
        self.error = nil
        
        Task {
            if let cachedFiles = await DirectoryCache.shared.getMacCache(for: url.path) {
                self.files = cachedFiles
                self.isLoading = false
            } else {
                self.isLoading = true
                self.files = []
            }
            self.selectedFileIDs.removeAll()
            
            do {
                let fetchedFiles = try directoryService.listDirectory(url)
                
                if self.files != fetchedFiles {
                    self.files = fetchedFiles
                    await DirectoryCache.shared.setMacCache(for: url.path, files: fetchedFiles)
                }
                
                self.isLoading = false
                
                DiagnosticLogger.shared.log("Directory Loaded (Mac): \(url.path)", category: .directory)
            } catch {
                if self.files.isEmpty {
                    self.error = error.localizedDescription
                }
                self.isLoading = false
            }
        }
    }
    
    func navigateUp() {
        guard let current = currentURL else { return }
        
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? "/")
        
        if current.path == root.path || current.path == "/" {
            return
        }
        
        let parent = current.deletingLastPathComponent()
        loadDirectory(parent)
    }
    
    func refresh() {
        guard let current = currentURL else { return }
        loadDirectory(current)
    }
    
    func reloadCurrentDirectory(selecting newFileID: String? = nil, fallbackIndex: Int? = nil) {
        guard let current = currentURL else { return }
        
        print("[DEBUG-SYNC] 1. reloadCurrentDirectory() called for \(current.path). Target selection: \(newFileID ?? "nil")")
        
        Task {
            do {
                let fetchedFiles = try directoryService.listDirectory(current)
                print("[DEBUG-SYNC] 2. Fetched \(fetchedFiles.count) files from disk.")
                
                if self.files != fetchedFiles {
                    print("[DEBUG-SYNC] 3. Data differs. Replacing self.files array. Old count: \(self.files.count), New count: \(fetchedFiles.count)")
                    self.files = fetchedFiles
                    await DirectoryCache.shared.setMacCache(for: current.path, files: fetchedFiles)
                    print("[DEBUG-SYNC] 4. New snapshot published to observers.")
                } else {
                    print("[DEBUG-SYNC] 3. Data is identical (self.files == fetchedFiles). No array replacement.")
                }
                
                if let newFile = newFileID {
                    print("[DEBUG-SYNC] 5. Updating selection to \(newFile)")
                    self.selectedFileIDs = [newFile]
                } else if let idx = fallbackIndex, !fetchedFiles.isEmpty {
                    let safeIdx = min(idx, fetchedFiles.count - 1)
                    self.selectedFileIDs = [fetchedFiles[safeIdx].id]
                    print("[DEBUG-SYNC] 5. Updating selection to nearest index \(safeIdx)")
                } else if fallbackIndex != nil {
                    self.selectedFileIDs = []
                }
            } catch {
                print("[DEBUG-SYNC] Failed to reload directory: \(error)")
            }
        }
    }
}
