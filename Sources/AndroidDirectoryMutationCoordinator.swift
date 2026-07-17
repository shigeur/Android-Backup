import Foundation

@MainActor
class AndroidDirectoryMutationCoordinator {
    private let viewModel: DirectoryViewModel
    
    init(viewModel: DirectoryViewModel) {
        self.viewModel = viewModel
    }
    
    func createFolder(name: String, device: AndroidDevice) async throws {
        let current = viewModel.currentPath
        print("[DebugLogger] Android Folder Creation Started: \(name) in \(current)")
        
        let newPath = try await FileOperationService.shared.newAndroidFolder(device: device, parentPath: current, name: name)
        
        viewModel.reloadCurrentDirectory(selecting: newPath)
    }
    
    func delete(paths: [String], device: AndroidDevice) async throws {
        print("[DirectoryMutationCoordinator] Delete Started (\(paths.count) items)")
        
        let firstDeletedPath = paths.first ?? ""
        let fallbackIndex = viewModel.files.firstIndex(where: { $0.id == firstDeletedPath }) ?? 0
        
        await FileOperationService.shared.deleteAndroidFiles(device: device, paths: paths)
        
        if FileOperationService.shared.error == nil {
            print("[DirectoryMutationCoordinator] Delete Completed")
            print("[DirectoryMutationCoordinator] Directory Cache Invalidated")
            print("[DirectoryMutationCoordinator] reloadCurrentDirectory()")
            
            viewModel.reloadCurrentDirectory(fallbackIndex: fallbackIndex)
            
            print("[DirectoryMutationCoordinator] Directory Snapshot Updated")
            print("[DirectoryMutationCoordinator] NSTableView Reloaded")
            print("[DirectoryMutationCoordinator] Selection Restored")
        } else {
            throw NSError(domain: "DirectoryMutation", code: 1, userInfo: [NSLocalizedDescriptionKey: FileOperationService.shared.error ?? "Unknown Error"])
        }
    }
}
