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
    
    func startBackgroundPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshDevices()
            }
        }
    }
    
    func refreshDevices() async {
        do {
            let output = try await ADBManager.shared.run(["devices", "-l"])
            let lines = output.components(separatedBy: .newlines)
            var newDevices: [AndroidDevice] = []
            
            for line in lines {
                if line.starts(with: "List of devices") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                    continue
                }
                
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 2 else { continue }
                
                let serial = String(parts[0])
                let status = String(parts[1])
                var model = "Unknown Device"
                
                for part in parts {
                    if part.starts(with: "model:") {
                        model = String(part.dropFirst("model:".count)).replacingOccurrences(of: "_", with: " ")
                    }
                }
                
                var device = AndroidDevice(serial: serial, model: model, status: status)
                
                // If device is active, fetch more info
                if status == "device" {
                    device = await fetchDeviceInfo(device)
                }
                
                newDevices.append(device)
            }
            
            self.connectedDevices = newDevices
            
            if let selected = selectedDevice, !newDevices.contains(where: { $0.serial == selected.serial }) {
                self.selectedDevice = nil
            } else if selectedDevice == nil, let first = newDevices.first {
                self.selectedDevice = first
            }
            
        } catch {
            print("Failed to fetch devices: \(error)")
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
