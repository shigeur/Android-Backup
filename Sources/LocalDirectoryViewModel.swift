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
}
