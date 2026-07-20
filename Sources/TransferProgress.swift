import Foundation

public enum TransferStage: String, Codable, CaseIterable {
    case requested = "Transfer Requested"
    case validation = "Validation"
    case duplicateDetection = "Duplicate Detection"
    case generatingPlan = "Generating Transfer Plan"
    case waitingForConfirmation = "Waiting For Confirmation"
    case preparing = "Preparing Transfer"
    case started = "Transfer Started"
    case copying = "Copying Files"
    case verifying = "Verifying"
    case refreshing = "Refreshing Destination"
    case completed = "Completed"
    case cancelled = "Cancelled"
    case failed = "Failed"
    case interrupted = "Interrupted"
}

public struct TransferProgress {
    public let sessionID: String
    public let stage: TransferStage
    public let percentage: Double
    public let filesCompleted: Int
    public let totalFiles: Int
    public let bytesCopied: Int64
    public let totalBytes: Int64
    public let currentFileName: String
    public let estimatedRemainingTime: TimeInterval?
    public let errorMessage: String?
    
    public init(sessionID: String, stage: TransferStage, percentage: Double = 0.0, filesCompleted: Int = 0, totalFiles: Int = 0, bytesCopied: Int64 = 0, totalBytes: Int64 = 0, currentFileName: String = "", estimatedRemainingTime: TimeInterval? = nil, errorMessage: String? = nil) {
        self.sessionID = sessionID
        self.stage = stage
        self.percentage = percentage
        self.filesCompleted = filesCompleted
        self.totalFiles = totalFiles
        self.bytesCopied = bytesCopied
        self.totalBytes = totalBytes
        self.currentFileName = currentFileName
        self.estimatedRemainingTime = estimatedRemainingTime
        self.errorMessage = errorMessage
    }
}
