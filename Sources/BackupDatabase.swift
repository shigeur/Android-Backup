import Foundation
import GRDB

class BackupDatabase {
    static let shared = BackupDatabase()
    var dbQueue: DatabaseQueue!
    
    private init() {}
    
    func initialize() throws {
        let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDirectory = appSupportURL.appendingPathComponent("AndroidBackup")
        try FileManager.default.createDirectory(at: dbDirectory, withIntermediateDirectories: true)
        
        let dbPath = dbDirectory.appendingPathComponent("backup_state.sqlite").path
        dbQueue = try DatabaseQueue(path: dbPath)
        
        try migrator.migrate(dbQueue)
    }
    
    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        
        #if DEBUG
        // migrator.eraseDatabaseOnSchemaChange = true // Use during active development if needed
        #endif
        
        migrator.registerMigration("v1") { db in
            // Application Settings
            try db.create(table: ApplicationSetting.databaseTableName) { t in
                t.column("key", .text).primaryKey()
                t.column("value", .text).notNull()
                t.column("valueType", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            
            // Backup Devices
            try db.create(table: BackupDevice.databaseTableName) { t in
                t.column("serial", .text).primaryKey()
                t.column("model", .text).notNull()
                t.column("lastConnectedAt", .datetime).notNull()
            }
            
            // Backup Sessions
            try db.create(table: BackupSession.databaseTableName) { t in
                t.column("id", .text).primaryKey()
                t.column("deviceSerial", .text).notNull().references(BackupDevice.databaseTableName, column: "serial", onDelete: .cascade)
                t.column("startedAt", .datetime).notNull()
                t.column("finishedAt", .datetime)
                t.column("status", .text).notNull()
                t.column("totalFiles", .integer).notNull()
                t.column("transferredFiles", .integer).notNull()
                t.column("totalBytes", .integer).notNull()
                t.column("transferredBytes", .integer).notNull()
            }
            
            // Backup Files
            try db.create(table: BackupFile.databaseTableName) { t in
                t.column("id", .text).primaryKey() // deviceSerial:relativePath
                t.column("deviceSerial", .text).notNull().references(BackupDevice.databaseTableName, column: "serial", onDelete: .cascade)
                t.column("sessionId", .text).references(BackupSession.databaseTableName, column: "id", onDelete: .setNull)
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
        
        return migrator
    }
}
