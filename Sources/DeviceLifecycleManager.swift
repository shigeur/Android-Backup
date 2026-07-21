import Foundation
import Combine

enum DeviceConnectionState: Equatable {
    case idle
    case searching
    case connected(AndroidDevice)
    case initializing(AndroidDevice)
    case ready(AndroidDevice)
    case disconnected
    case unauthorized
    case adbMissing
    case adbOffline
    case error(String)
    
    static func == (lhs: DeviceConnectionState, rhs: DeviceConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.searching, .searching), (.disconnected, .disconnected),
             (.unauthorized, .unauthorized), (.adbMissing, .adbMissing), (.adbOffline, .adbOffline):
            return true
        case (.error(let l), .error(let r)): return l == r
        case (.connected(let l), .connected(let r)): return l.serial == r.serial && l.status == r.status
        case (.initializing(let l), .initializing(let r)): return l.serial == r.serial && l.status == r.status
        case (.ready(let l), .ready(let r)): return l.serial == r.serial && l.status == r.status
        default: return false
        }
    }
}

extension DeviceLifecycleManager {
    var currentDevice: AndroidDevice? {
        if case .ready(let device) = state { return device }
        if case .initializing(let device) = state { return device }
        if case .connected(let device) = state { return device }
        return nil
    }
}

@MainActor
class DeviceLifecycleManager: ObservableObject {
    static let shared = DeviceLifecycleManager()
    
    @Published private(set) var state: DeviceConnectionState = .idle
    
    private var searchTask: Task<Void, Never>?
    private var currentSearchSessionId: UUID?
    
    private init() {}
    
    func startSearch() {
        // Stop any existing search
        stopSearch()
        
        let sessionId = UUID()
        currentSearchSessionId = sessionId
        updateState(.searching)
        
        searchTask = Task {
            await runSearchLoop(sessionId: sessionId)
        }
    }
    
    func stopSearch() {
        searchTask?.cancel()
        searchTask = nil
        currentSearchSessionId = nil
        print("[\(Date())] Search Session Cancelled")
    }
    
    func refreshManually() {
        print("[\(Date())] Refresh Requested")
        startSearch()
    }
    
    func disconnect() {
        print("[\(Date())] Device Disconnected")

        updateState(.disconnected)
        startSearch()
    }
    
    func handleAdbError(_ errorMsg: String) {
        if errorMsg.contains("not found") {
            updateState(.adbMissing)
        } else if errorMsg.contains("server") {
            updateState(.adbOffline)
        } else {
            updateState(.error(errorMsg))
        }
    }
    
    private func updateState(_ newState: DeviceConnectionState) {
        if state != newState {
            print("[\(Date())] Transition: \(state) -> \(newState)")
            state = newState
            DiagnosticLogger.shared.log("Device state changed to: \(newState)", category: .device)
        } else {
            print("[\(Date())] State Transition Ignored: \(newState)")
        }
    }
    
    private func runSearchLoop(sessionId: UUID) async {
        print("[\(Date())] Search Session Created (\(sessionId))")
        print("[\(Date())] Searching Started")
        
        while !Task.isCancelled && currentSearchSessionId == sessionId {
            do {
                let devices = try await ADBManager.shared.getConnectedDevices()
                
                if Task.isCancelled || currentSearchSessionId != sessionId { return }
                
                if let device = devices.first {
                    if device.status == "unauthorized" {
                        updateState(.unauthorized)
                    } else if device.status == "device" {
                        // Found a valid device!
                        
                        // Check if it's the exact same device we already have ready
                        if case .ready(let currentDevice) = state, currentDevice.serial == device.serial {
                            // Device is still connected and ready. Keep polling.
                        } else if case .initializing(let currentDevice) = state, currentDevice.serial == device.serial {
                            // Device is still initializing. Keep polling.
                        } else {
                        
                        print("[\(Date())] Device Connected")
                        updateState(.connected(device))
                        
                        // Hand off to DeviceManager for initialization
                        updateState(.initializing(device))
                        
                        if let initializedDevice = await DeviceManager.shared.initializeDevice(device) {
                            print("[\(Date())] Device Ready")
                            updateState(.ready(initializedDevice))
                        } else {
                            updateState(.error("Failed to initialize device"))
                        }
                    }
                }
            } else {
                    if state != .searching && state != .disconnected && state != .unauthorized {
                        updateState(.disconnected)
                        await DirectoryCache.shared.invalidateAllAndroid()
                    }
                }
            } catch {
                if Task.isCancelled || currentSearchSessionId != sessionId { return }
                handleAdbError(error.localizedDescription)
            }
            
            // Wait before polling again
            if !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            }
        }
    }
}
