import Foundation
import SwiftUI

@MainActor
class DirectoryViewModel: ObservableObject {
    @Published var currentPath: String = "/"
    @Published var files: [ADBFile] = []
    @Published var selectedFileIDs: Set<String> = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil
    
    private let directoryService: DirectoryService
    
    init(device: AndroidDevice) {
        self.directoryService = DirectoryService(device: device)
    }
    
    func loadDirectory(_ path: String) {
        self.currentPath = path
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
}
