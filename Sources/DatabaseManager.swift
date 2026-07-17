import Foundation
import GRDB

struct FileRecord: Codable, FetchableRecord, PersistableRecord, Equatable {
    var id: String { deviceSerial + ":" + relativePath }
    let deviceSerial: String
    let relativePath: String
    let filename: String
    let size: Int64
    let modifiedDate: Date
    let sha256: String?
    let transferDate: Date
    let destinationFolder: String
    let verificationStatus: String
}

class DatabaseManager {
    static let shared = DatabaseManager()
    var dbQueue: DatabaseQueue?
    
    init() {
        do {
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dbDirectory = appSupportURL.appendingPathComponent("AndroidBackup")
            try FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
            
            let dbPath = dbDirectory.appendingPathComponent("backup_state.sqlite").path
            dbQueue = try DatabaseQueue(path: dbPath)
            try setupSchema()
        } catch {
            print("Failed to initialize database: \(error)")
        }
    }
    
    private func setupSchema() throws {
        try dbQueue?.write { db in
            try db.drop(table: "fileRecord")
            try db.create(table: "fileRecord", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("deviceSerial", .text).notNull().indexed()
                t.column("relativePath", .text).notNull()
                t.column("filename", .text).notNull()
                t.column("size", .integer).notNull()
                t.column("modifiedDate", .datetime).notNull()
                t.column("sha256", .text)
                t.column("transferDate", .datetime).notNull()
                t.column("destinationFolder", .text).notNull()
                t.column("verificationStatus", .text).notNull()
            }
        }
    }
    
    func saveRecord(_ record: FileRecord) throws {
        try dbQueue?.write { db in
            try record.save(db)
        }
    }
    
    func getRecord(deviceSerial: String, relativePath: String) throws -> FileRecord? {
        try dbQueue?.read { db in
            let id = "\(deviceSerial):\(relativePath)"
            return try FileRecord.fetchOne(db, key: id)
        }
    }
}
