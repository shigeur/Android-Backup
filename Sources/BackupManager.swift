import Foundation

@MainActor
class BackupManager: ObservableObject {
    static let shared = BackupManager()
    
    private let repository = BackupRepository.shared
    
    private init() {}
    
    func initialize() {
        // Will be called during ApplicationStartupCoordinator sequence
    }
}
