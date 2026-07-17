import Foundation

@MainActor
class LocalDirectoryMutationCoordinator {
    private let viewModel: LocalDirectoryViewModel
    
    init(viewModel: LocalDirectoryViewModel) {
        self.viewModel = viewModel
    }
    
    func createFolder(name: String) async throws {
        guard let current = viewModel.currentURL else { return }
        print("[DEBUG-SYNC] 0. Filesystem mutation started: Create Folder (\(name))")
        
        let newURL = try await FileOperationService.shared.newMacFolder(parentURL: current, name: name)
        
        print("[DEBUG-SYNC] 0.5. Filesystem mutation completed on disk")
        
        viewModel.reloadCurrentDirectory(selecting: newURL.path)
    }
    
    func rename(url: URL, newName: String) async throws {
        print("[DirectoryMutationCoordinator] Filesystem mutation started: Rename (\(url.lastPathComponent) -> \(newName))")
        
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)
        await FileOperationService.shared.renameMacFile(url: url, newName: newName)
        
        if FileOperationService.shared.error == nil {
            print("[DirectoryMutationCoordinator] Filesystem mutation completed")
            print("[DirectoryMutationCoordinator] Directory cache invalidated")
            
            viewModel.reloadCurrentDirectory(selecting: newURL.path)
            
            print("[DirectoryMutationCoordinator] Directory reloaded")
            print("[DirectoryMutationCoordinator] New snapshot published")
            print("[DirectoryMutationCoordinator] NSTableView reloaded")
            print("[DirectoryMutationCoordinator] Selection restored")
        } else {
            print("[DirectoryMutationCoordinator] Filesystem mutation failed")
            throw NSError(domain: "DirectoryMutation", code: 1, userInfo: [NSLocalizedDescriptionKey: FileOperationService.shared.error ?? "Unknown Error"])
        }
    }
    
    func delete(urls: [URL]) async throws {
        print("[DirectoryMutationCoordinator] Filesystem mutation started: Delete (\(urls.count) items)")
        
        let firstDeletedUrl = urls.first?.path ?? ""
        let fallbackIndex = viewModel.files.firstIndex(where: { $0.id == firstDeletedUrl }) ?? 0
        
        await FileOperationService.shared.deleteMacFiles(urls: urls)
        
        if FileOperationService.shared.error == nil {
            print("[DirectoryMutationCoordinator] Filesystem mutation completed")
            print("[DirectoryMutationCoordinator] Directory cache invalidated")
            
            // Just reload, selecting nothing for simplicity right now
            viewModel.reloadCurrentDirectory(fallbackIndex: fallbackIndex)
            
            print("[DirectoryMutationCoordinator] Directory reloaded")
            print("[DirectoryMutationCoordinator] New snapshot published")
            print("[DirectoryMutationCoordinator] NSTableView reloaded")
            print("[DirectoryMutationCoordinator] Selection restored")
        } else {
            print("[DirectoryMutationCoordinator] Filesystem mutation failed")
            throw NSError(domain: "DirectoryMutation", code: 1, userInfo: [NSLocalizedDescriptionKey: FileOperationService.shared.error ?? "Unknown Error"])
        }
    }
    
    func duplicate(urls: [URL]) async throws {
        print("[DirectoryMutationCoordinator] Filesystem mutation started: Duplicate (\(urls.count) items)")
        
        await FileOperationService.shared.duplicateMacFiles(urls: urls)
        
        print("[DirectoryMutationCoordinator] Filesystem mutation completed")
        print("[DirectoryMutationCoordinator] Directory cache invalidated")
        
        viewModel.reloadCurrentDirectory(selecting: nil)
        
        print("[DirectoryMutationCoordinator] Directory reloaded")
        print("[DirectoryMutationCoordinator] New snapshot published")
        print("[DirectoryMutationCoordinator] NSTableView reloaded")
        print("[DirectoryMutationCoordinator] Selection restored")
    }
    
    func performPaste(item: ClipboardItem, destination: URL) async throws {
        print("[DirectoryMutationCoordinator] Filesystem mutation started: Paste (\(item.paths.count) items)")
        
        if item.platform == .mac {
            let urls = item.paths.map { URL(fileURLWithPath: $0) }
            if item.action == .copy {
                // Duplicate into the current directory
                // Wait! FileOperationService duplicateMacFiles currently duplicates IN PLACE (same directory as source)
                // If destination is different, it needs a copy item implementation
                // We should add copyMacFiles(urls: [URL], to: URL) to FileOperationService
                await FileOperationService.shared.copyMacFiles(urls: urls, to: destination)
            } else if item.action == .cut {
                await FileOperationService.shared.moveMacFiles(urls: urls, to: destination)
            }
        }
        
        print("[DirectoryMutationCoordinator] Filesystem mutation completed")
        print("[DirectoryMutationCoordinator] Directory cache invalidated")
        
        viewModel.reloadCurrentDirectory(selecting: nil)
        
        print("[DirectoryMutationCoordinator] Directory reloaded")
        print("[DirectoryMutationCoordinator] New snapshot published")
        print("[DirectoryMutationCoordinator] NSTableView reloaded")
        print("[DirectoryMutationCoordinator] Selection restored")
    }
}
