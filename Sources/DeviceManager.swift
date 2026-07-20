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
class DeviceManager {
    static let shared = DeviceManager()
    
    private init() {}
    
    func initializeDevice(_ device: AndroidDevice) async -> AndroidDevice? {
        let startTime = Date()
        print("[\(startTime)] InitializeDevice() Started")
        do {
            let populatedDevice = try await fetchDeviceInfo(device)
            
            print("[\(Date())] LoadRootDirectory() Started")
            let rootStart = Date()
            // Load Initial Directory
            let dirService = DirectoryService(device: populatedDevice)
            let files = try await dirService.listDirectory("/")
            await DirectoryCache.shared.setAndroidCache(for: "/", files: files)
            print("[\(Date())] LoadRootDirectory() Finished in \(Date().timeIntervalSince(rootStart))s")
            
            print("[\(Date())] PublishReady()")
            print("[\(Date())] InitializeDevice() Finished in \(Date().timeIntervalSince(startTime))s")
            return populatedDevice
        } catch {
            print("[DeviceManager] Error during InitializeDevice(): \(error.localizedDescription) - failed after \(Date().timeIntervalSince(startTime))s")
            return nil
        }
    }
    
    private func fetchDeviceInfo(_ device: AndroidDevice) async throws -> AndroidDevice {
        var updatedDevice = device
        
        let versionStart = Date()
        print("[\(versionStart)] LoadAndroidVersion() Started")
        // Fetch Android version
        let versionStr = try await ADBManager.shared.run(["-s", device.serial, "shell", "getprop", "ro.build.version.release"])
        let version = versionStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if version.isEmpty {
            throw NSError(domain: "DeviceManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Android version not ready"])
        }
        updatedDevice.androidVersion = version
        print("[\(Date())] LoadAndroidVersion() Finished in \(Date().timeIntervalSince(versionStart))s")
        
        let batteryStart = Date()
        print("[\(batteryStart)] LoadBattery() Started")
        // Fetch Battery Level
        let batteryDump = try await ADBManager.shared.run(["-s", device.serial, "shell", "dumpsys", "battery"])
        let lines = batteryDump.components(separatedBy: .newlines)
        var foundBattery = false
        for line in lines {
            if line.contains("level:") {
                let parts = line.split(separator: ":", omittingEmptySubsequences: true)
                if parts.count == 2, let level = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                    updatedDevice.batteryLevel = level
                    foundBattery = true
                }
            }
        }
        if !foundBattery {
            throw NSError(domain: "DeviceManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Battery level not ready"])
        }
        print("[\(Date())] LoadBattery() Finished in \(Date().timeIntervalSince(batteryStart))s")
        
        let storageStart = Date()
        print("[\(storageStart)] LoadStorage() Started")
        // Fetch Storage (simple df -k /data)
        let dfDump = try await ADBManager.shared.run(["-s", device.serial, "shell", "df", "-k", "/data"])
        let dfLines = dfDump.components(separatedBy: .newlines)
        if dfLines.count >= 2 {
            let parts = dfLines[1].split(separator: " ", omittingEmptySubsequences: true)
            // Filesystem 1K-blocks Used Available Use% Mounted on
            if parts.count >= 4 {
                if let totalKB = Int64(parts[1]), let freeKB = Int64(parts[3]) {
                    updatedDevice.storageTotalBytes = totalKB * 1024
                    updatedDevice.storageFreeBytes = freeKB * 1024
                } else {
                    throw NSError(domain: "DeviceManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Storage parsing failed"])
                }
            } else {
                throw NSError(domain: "DeviceManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Storage parts missing"])
            }
        } else {
            throw NSError(domain: "DeviceManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "Storage lines missing"])
        }
        print("[\(Date())] LoadStorage() Finished in \(Date().timeIntervalSince(storageStart))s")
        
        return updatedDevice
    }
}
