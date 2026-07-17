import Foundation
import Combine

struct AndroidDevice: Identifiable, Equatable {
    var id: String { serial }
    let serial: String
    let model: String
    let status: String
    var batteryLevel: Int?
    var storageTotalBytes: Int64?
    var storageFreeBytes: Int64?
    var androidVersion: String?
}

@MainActor
class DeviceManager: ObservableObject {
    @Published var connectedDevices: [AndroidDevice] = []
    @Published var selectedDevice: AndroidDevice?
    static let shared = DeviceManager()
    
    private var timer: Timer?
    
    private init() {}
    
    func clearSelection() {
        selectedDevice = nil
        connectedDevices = []
    }
    
    func initializeDevice(_ device: AndroidDevice) async -> Bool {
        do {
            let populatedDevice = await fetchDeviceInfo(device)
            self.connectedDevices = [populatedDevice]
            self.selectedDevice = populatedDevice
            
            // Load Initial Directory
            let dirService = DirectoryService(device: populatedDevice)
            let files = try await dirService.listDirectory("/")
            await DirectoryCache.shared.setAndroidCache(for: "/", files: files)
            print("[\(Date())] Directory Loaded")
            
            return true
        } catch {
            print("[DeviceManager] Error loading initial directory: \(error)")
            return false
        }
    }
    
    private func fetchDeviceInfo(_ device: AndroidDevice) async -> AndroidDevice {
        var updatedDevice = device
        
        // Fetch Android version
        if let versionStr = try? await ADBManager.shared.run(["-s", device.serial, "shell", "getprop", "ro.build.version.release"]) {
            updatedDevice.androidVersion = versionStr
        }
        
        // Fetch Battery Level
        if let batteryDump = try? await ADBManager.shared.run(["-s", device.serial, "shell", "dumpsys", "battery"]) {
            let lines = batteryDump.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("level:") {
                    let parts = line.split(separator: ":", omittingEmptySubsequences: true)
                    if parts.count == 2, let level = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                        updatedDevice.batteryLevel = level
                    }
                }
            }
        }
        
        // Fetch Storage (simple df -k /data)
        if let dfDump = try? await ADBManager.shared.run(["-s", device.serial, "shell", "df", "-k", "/data"]) {
            let lines = dfDump.components(separatedBy: .newlines)
            if lines.count >= 2 {
                let parts = lines[1].split(separator: " ", omittingEmptySubsequences: true)
                // Filesystem 1K-blocks Used Available Use% Mounted on
                if parts.count >= 4 {
                    if let totalKB = Int64(parts[1]), let freeKB = Int64(parts[3]) {
                        updatedDevice.storageTotalBytes = totalKB * 1024
                        updatedDevice.storageFreeBytes = freeKB * 1024
                    }
                }
            }
        }
        
        return updatedDevice
    }
}
