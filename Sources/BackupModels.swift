import Foundation
import GRDB

struct BackupDevice: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "backupDevices"
    
    var serial: String
    var model: String
    var lastConnectedAt: Date
}

struct BackupSession: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "backupSessions"
    
    var id: String // UUID
    var deviceSerial: String
    var startedAt: Date
    var finishedAt: Date?
    var status: String // "running", "completed", "failed", "cancelled"
    var totalFiles: Int
    var transferredFiles: Int
    var totalBytes: Int64
    var transferredBytes: Int64
}

struct BackupFile: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "backupFiles"
    
    var id: String { deviceSerial + ":" + relativePath }
    var deviceSerial: String
    var sessionId: String?
    var relativePath: String
    var filename: String
    var size: Int64
    var modifiedDate: Date
    var sha256: String?
    var transferDate: Date
    var destinationFolder: String
    var verificationStatus: String
}
