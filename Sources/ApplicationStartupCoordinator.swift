import Foundation
import Combine

enum ApplicationState: Equatable {
    case launching
    case initializingADB
    case ready
    case error(String)
}

@MainActor
class ApplicationStartupCoordinator: ObservableObject {
    static let shared = ApplicationStartupCoordinator()
    
    @Published var state: ApplicationState = .launching
    
    private let adbManager = ADBManager.shared
    
    private init() {}
    
    func start() {
        guard state == .launching || state == .error("") else { return } // Allow retry on error
        
        state = .launching
        
        Task {
            print("[ApplicationStartupCoordinator] Application launched")
            
            // 1. BackupDatabase
            do {
                try BackupDatabase.shared.initialize()
                print("[ApplicationStartupCoordinator] BackupDatabase initialized")
            } catch {
                state = .error("Failed to initialize database: \(error.localizedDescription)")
                return
            }
            
            // 2. ApplicationSettings (SettingsManager)
            SettingsManager.shared.loadAllSettings()
            print("[ApplicationStartupCoordinator] SettingsManager initialized")
            
            // 3. ADBManager
            state = .initializingADB
            
            if !SettingsManager.shared.manualAdbPath.isEmpty {
                adbManager.adbPath = SettingsManager.shared.manualAdbPath
            }
            
            _ = await adbManager.discoverADB()
            print("[ApplicationStartupCoordinator] ADB initialized. Path: \(adbManager.adbPath)")
            
            if !adbManager.adbPath.isEmpty {
                if let version = try? await adbManager.run(["version"]) {
                    print("[ApplicationStartupCoordinator] ADB version detected: \(version.components(separatedBy: .newlines).first ?? "")")
                }
                print("[ApplicationStartupCoordinator] ADB server started")
            } else {
                state = .error("ADB not found. Please install Android Platform Tools.")
                return
            }
            
            // 4. BackupRepository & BackupManager
            BackupManager.shared.initialize()
            print("[ApplicationStartupCoordinator] BackupRepository and BackupManager initialized")
            
            // 5. Shared ApplicationState -> Ready
            state = .ready
            print("[ApplicationStartupCoordinator] Application ready. Handing off to DeviceLifecycleManager.")
            
            DeviceLifecycleManager.shared.startSearch()
        }
    }
}
