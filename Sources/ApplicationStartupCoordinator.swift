import Foundation
import Combine

enum ApplicationState: Equatable {
    case launching
    case initializingADB
    case detectingDevices
    case loadingInitialDirectory
    case ready
    case noDevice
    case error(String)
}

@MainActor
class ApplicationStartupCoordinator: ObservableObject {
    static let shared = ApplicationStartupCoordinator()
    
    @Published var state: ApplicationState = .launching
    
    private let adbManager = ADBManager.shared
    private let deviceManager = DeviceManager.shared
    
    private init() {}
    
    func start() {
        guard state == .launching else { return }
        
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
            
            // If manual path was set in settings, adbManager should prioritize it
            // ADBManager could be injected or we just configure it here if needed.
            // For now, discoverADB handles auto-discovery or we could inject the path.
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
            }
            
            // 4. DeviceManager
            state = .detectingDevices
            await deviceManager.refreshDevices()
            
            // 5. BackupRepository & BackupManager
            BackupManager.shared.initialize()
            print("[ApplicationStartupCoordinator] BackupRepository and BackupManager initialized")
            
            if let device = deviceManager.selectedDevice {
                print("[ApplicationStartupCoordinator] Device selected: \(device.model) (\(device.serial))")
                
                // Load Initial Directory
                state = .loadingInitialDirectory
                let dirService = DirectoryService(device: device)
                do {
                    let files = try await dirService.listDirectory("/")
                    await DirectoryCache.shared.setAndroidCache(for: "/", files: files)
                    print("[ApplicationStartupCoordinator] Initial directory loaded and cache initialized")
                    
                    // 6. Shared ApplicationState -> Ready
                    state = .ready
                    print("[ApplicationStartupCoordinator] Application ready")
                } catch {
                    print("[ApplicationStartupCoordinator] Error loading initial directory: \(error)")
                    state = .error("Failed to load initial directory: \(error.localizedDescription)")
                }
                
            } else {
                print("[ApplicationStartupCoordinator] No device detected")
                state = .noDevice
            }
            
            deviceManager.startBackgroundPolling()
        }
    }
}
