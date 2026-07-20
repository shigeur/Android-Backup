import Foundation
import Combine

@MainActor
class TransferEngine {
    static let shared = TransferEngine()
    
    public typealias TransferProgressCallback = (TransferProgress) -> Void
    
    func executePaste(destPlatform: FilePlatform, destPath: String, destURL: URL, onProgress: TransferProgressCallback? = nil) {
        print("[DebugLogger] TransferEngine executePaste: destPlatform=\(destPlatform), destPath=\(destPath)")
        DiagnosticLogger.shared.log("Execute Paste Requested: destPlatform=\(destPlatform)", category: .transfer)
        
        guard let item = ClipboardManager.shared.currentItem else { 
            print("[DebugLogger] TransferEngine Error: ClipboardManager has no current item.")
            DiagnosticLogger.shared.log("Paste failed: Clipboard empty", category: .transfer)
            return 
        }
        
        print("[DebugLogger] TransferEngine paste executing for \(item.paths.count) items from \(item.platform)")
        executeTransfer(
            action: item.action,
            sourcePlatform: item.platform,
            sourceDeviceSerial: item.sourceDeviceSerial,
            sourcePaths: item.paths,
            destPlatform: destPlatform,
            destPath: destPath,
            destURL: destURL,
            onProgress: onProgress
        )
        
        if item.action == .cut {
            print("[DebugLogger] TransferEngine clearing clipboard after Cut paste")
            ClipboardManager.shared.clear()
        }
    }
    
    func executeTransfer(action: ClipboardAction, sourcePlatform: FilePlatform, sourceDeviceSerial: String?, sourcePaths: [String], destPlatform: FilePlatform, destPath: String, destURL: URL, onProgress: TransferProgressCallback? = nil) {
        print("[DebugLogger] TransferEngine executeTransfer: action=\(action), srcPlatform=\(sourcePlatform), destPlatform=\(destPlatform), count=\(sourcePaths.count), dest=\(destPath)")
        let sessionID = UUID().uuidString.prefix(8).uppercased()
        
        let wrappedProgress: TransferProgressCallback = { progress in
            print("[TransferSession \(progress.sessionID)] \(progress.stage.rawValue) ↓")
            
            // Log to Diagnostic Panel
            let message = "Session \(progress.sessionID): \(progress.stage.rawValue) - \(progress.percentage ?? 0.0)%"
            DiagnosticLogger.shared.log(message, category: .transfer)
            
            onProgress?(progress)
        }
        
        wrappedProgress(TransferProgress(sessionID: sessionID, stage: .requested))
        
        Task {
            if sourcePlatform == .mac && destPlatform == .mac {
                let urls = sourcePaths.map { URL(fileURLWithPath: $0) }
                if action == .cut {
                    await FileOperationService.shared.moveMacFiles(urls: urls, to: destURL, sessionID: sessionID, onProgress: wrappedProgress)
                } else {
                    await FileOperationService.shared.copyMacFiles(urls: urls, to: destURL, sessionID: sessionID, onProgress: wrappedProgress)
                }
            } else if sourcePlatform == .android && destPlatform == .mac {
                guard let deviceSerial = sourceDeviceSerial, let device = DeviceManager.shared.selectedDevice, device.serial == deviceSerial else { 
                    wrappedProgress(TransferProgress(sessionID: sessionID, stage: .failed, errorMessage: "Device not found or not matching."))
                    return 
                }
                await TransferService.shared.prepareTransfer(device: device, direction: .androidToMac, sourcePaths: sourcePaths, destination: destURL, isBackup: false, sessionID: sessionID, onProgress: wrappedProgress)
            } else if sourcePlatform == .mac && destPlatform == .android {
                guard let device = DeviceManager.shared.selectedDevice else { 
                    wrappedProgress(TransferProgress(sessionID: sessionID, stage: .failed, errorMessage: "No device connected."))
                    return 
                }
                // For mac to android, TransferService expects destination to be URL
                let dest = URL(fileURLWithPath: destPath)
                await TransferService.shared.prepareTransfer(device: device, direction: .macToAndroid, sourcePaths: sourcePaths, destination: dest, isBackup: false, sessionID: sessionID, onProgress: wrappedProgress)
            } else if sourcePlatform == .android && destPlatform == .android {
                // Not supported natively yet without file operation service support
                wrappedProgress(TransferProgress(sessionID: sessionID, stage: .failed, errorMessage: "Android to Android transfer not implemented."))
            }
        }
    }
}
