import Foundation
import Combine
import SwiftUI

@MainActor
class TransferSession: ObservableObject, Identifiable {
    let id: String
    let device: AndroidDevice?
    let direction: TransferDirection?
    let destination: URL
    let isBackup: Bool
    
    @Published public var state: TransferState = .idle
    @Published public var totalFiles: Int = 0
    @Published public var copiedFiles: Int = 0
    @Published public var skippedFiles: Int = 0
    @Published public var currentFile: String = ""
    @Published public var currentLocalPath: String = ""
    @Published public var currentRemotePath: String = ""
    @Published public var progress: Double = 0.0
    
    // Stats
    @Published public var bytesCopied: Int64 = 0
    @Published public var totalBytesToCopy: Int64 = 0
    @Published public var currentSpeedBytesPerSecond: Double = 0.0
    @Published public var peakSpeedBytesPerSecond: Double = 0.0
    @Published public var estimatedRemainingTime: TimeInterval? = nil
    
    // Scanning specific metrics
    @Published public var totalFoldersFound: Int = 0
    @Published public var totalBytesFound: Int64 = 0
    @Published public var scanningSpeedItemsPerSecond: Double = 0.0
    @Published public var isScanComplete: Bool = false
    
    @Published public var transferPlan: TransferPlan? = nil
    
    // Detailed Progress
    @Published public var elapsedTime: TimeInterval = 0
    @Published public var currentFileSize: Int64 = 0
    @Published public var currentFileBytesCopied: Int64 = 0
    
    public var currentFileProgress: Double {
        guard currentFileSize > 0 else { return 0 }
        return Double(currentFileBytesCopied) / Double(currentFileSize)
    }

    public var overallBytesTransferred: Int64 {
        return bytesCopied + currentFileBytesCopied
    }
    
    public var overallProgress: Double {
        guard totalBytesToCopy > 0 else { return 0 }
        return Double(overallBytesTransferred) / Double(totalBytesToCopy)
    }

    private var isCancelled = false
    private var progressTimer: AnyCancellable?
    private var estimatorTimer: AnyCancellable?
    private var activeTask: Task<Void, Never>?
    
    private var startTime: Date?
    private var fileStartTime: Date?
    
    init(id: String = UUID().uuidString.prefix(8).uppercased(), device: AndroidDevice?, direction: TransferDirection?, destination: URL, isBackup: Bool = false) {
        self.id = id
        self.device = device
        self.direction = direction
        self.destination = destination
        self.isBackup = isBackup
    }
    
    public func setActiveTask(_ task: Task<Void, Never>) {
        self.activeTask = task
    }
    
    public func cancel() {
        isCancelled = true
        activeTask?.cancel()
        cleanup()
    }
    
    public func checkCancelled() -> Bool {
        return isCancelled || Task.isCancelled
    }
    
    public func cleanup() {
        progressTimer?.cancel()
        progressTimer = nil
        estimatorTimer?.cancel()
        estimatorTimer = nil
    }
    
    public func startScanningTimer() {
        startTime = Date()
        progressTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self, !self.isScanComplete, let start = self.startTime else { return }
            self.elapsedTime = Date().timeIntervalSince(start)
            if self.elapsedTime > 0 {
                self.scanningSpeedItemsPerSecond = Double(self.totalFiles) / self.elapsedTime
            }
        }
    }
    
    public func stopScanningTimer() {
        isScanComplete = true
        progressTimer?.cancel()
        progressTimer = nil
    }
    
    public func startCopyingTimer() {
        startTime = Date()
        progressTimer?.cancel()
        progressTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self, let start = self.startTime else { return }
            self.elapsedTime = Date().timeIntervalSince(start)
            if self.elapsedTime > 0 {
                let totalCurrentBytes = self.bytesCopied + self.currentFileBytesCopied
                self.currentSpeedBytesPerSecond = Double(totalCurrentBytes) / self.elapsedTime
                if self.currentSpeedBytesPerSecond > self.peakSpeedBytesPerSecond {
                    self.peakSpeedBytesPerSecond = self.currentSpeedBytesPerSecond
                }
                
                let remainingBytes = Double(self.totalBytesToCopy) - Double(totalCurrentBytes)
                if self.currentSpeedBytesPerSecond > 0 && remainingBytes > 0 {
                    self.estimatedRemainingTime = remainingBytes / self.currentSpeedBytesPerSecond
                } else {
                    self.estimatedRemainingTime = nil
                }
            }
        }
    }
    
    public func startFileEstimator(fileSize: Int64) {
        self.currentFileSize = fileSize
        self.currentFileBytesCopied = 0
        self.fileStartTime = Date()
        
        estimatorTimer?.cancel()
        
        // Use average speed or a fallback (e.g. 25 MB/s)
        let speedToUse = self.currentSpeedBytesPerSecond > 0 ? self.currentSpeedBytesPerSecond : 25_000_000.0
        
        estimatorTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self, let fStart = self.fileStartTime else { return }
            let elapsedForFile = Date().timeIntervalSince(fStart)
            
            // Estimate bytes copied
            let estimatedBytes = Int64(speedToUse * elapsedForFile)
            // Cap at 95% of file size until it actually finishes
            let maxBytes = Int64(Double(fileSize) * 0.95)
            self.currentFileBytesCopied = min(estimatedBytes, maxBytes)
        }
    }
    
    public func finishCurrentFile() {
        estimatorTimer?.cancel()
        estimatorTimer = nil
        self.currentFileBytesCopied = self.currentFileSize
        self.copiedFiles += 1
        self.bytesCopied += self.currentFileSize
        self.currentFileBytesCopied = 0
        self.progress = Double(self.copiedFiles + self.skippedFiles) / Double(max(1, self.totalFiles))
    }
}

enum TransferDirection: String, Equatable {
    case macToAndroid
    case androidToMac
}

enum TransferState: Equatable {
    case idle
    case scanning
    case preflight
    case copying
    case verifying
    case finished
    case error(String)
}

enum DuplicateDetectionMode {
    case fast
    case balanced
}

class TransferPlan {
    let device: AndroidDevice?
    let direction: TransferDirection?
    let destination: URL
    let isBackup: Bool
    
    var newJobs: [TransferJob] = []
    var modifiedJobs: [TransferJob] = []
    var duplicateJobs: [TransferJob] = []
    
    var totalBytes: Int64 = 0
    var duplicateBytes: Int64 = 0
    
    init(device: AndroidDevice?, direction: TransferDirection?, destination: URL, isBackup: Bool) {
        self.device = device
        self.direction = direction
        self.destination = destination
        self.isBackup = isBackup
    }
}
