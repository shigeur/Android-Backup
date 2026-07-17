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
            
            // 1. Initializing ADB
            state = .initializingADB
            _ = await adbManager.discoverADB()
            print("[ApplicationStartupCoordinator] ADB initialized. Path: \(adbManager.adbPath)")
            
            if !adbManager.adbPath.isEmpty {
                if let version = try? await adbManager.run(["version"]) {
                    print("[ApplicationStartupCoordinator] ADB version detected: \(version.components(separatedBy: .newlines).first ?? "")")
                }
                print("[ApplicationStartupCoordinator] ADB server started")
            }
            
            // 2. Detecting Devices
            state = .detectingDevices
            await deviceManager.refreshDevices()
            
            if let device = deviceManager.selectedDevice {
                print("[ApplicationStartupCoordinator] Device selected: \(device.model) (\(device.serial))")
                
                // 3. Loading Initial Directory
                state = .loadingInitialDirectory
                
                let dirService = DirectoryService(device: device)
                do {
                    let files = try await dirService.listDirectory("/")
                    await DirectoryCache.shared.setAndroidCache(for: "/", files: files)
                    print("[ApplicationStartupCoordinator] Initial directory loaded and cache initialized")
                    
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
            
            // 4. Start Background Polling for devices changing
            deviceManager.startBackgroundPolling()
        }
    }
}
