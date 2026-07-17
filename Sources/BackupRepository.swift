import Foundation
import GRDB

class BackupRepository {
    static let shared = BackupRepository()
    private var dbQueue: DatabaseQueue { BackupDatabase.shared.dbQueue }
    
    private init() {}
    
    // MARK: - Devices
    func saveDevice(_ device: BackupDevice) throws {
        try dbQueue.write { db in
            try device.save(db)
        }
    }
    
    func getDevice(serial: String) throws -> BackupDevice? {
        try dbQueue.read { db in
            try BackupDevice.fetchOne(db, key: serial)
        }
    }
    
    // MARK: - Sessions
    func saveSession(_ session: BackupSession) throws {
        try dbQueue.write { db in
            try session.save(db)
        }
    }
    
    func getSession(id: String) throws -> BackupSession? {
        try dbQueue.read { db in
            try BackupSession.fetchOne(db, key: id)
        }
    }
    
    func getAllSessions() throws -> [BackupSession] {
        try dbQueue.read { db in
            try BackupSession.fetchAll(db)
        }
    }
    
    // MARK: - Files
    func saveFile(_ file: BackupFile) throws {
        try dbQueue.write { db in
            try file.save(db)
        }
    }
    
    func getFile(deviceSerial: String, relativePath: String) throws -> BackupFile? {
        try dbQueue.read { db in
            let id = "\(deviceSerial):\(relativePath)"
            return try BackupFile.fetchOne(db, key: id)
        }
    }
    
    func getFilesForSession(sessionId: String) throws -> [BackupFile] {
        try dbQueue.read { db in
            try BackupFile.filter(Column("sessionId") == sessionId).fetchAll(db)
        }
    }
    
    // MARK: - Deletion
    
    func deleteSessions(ids: Set<String>) throws {
        try dbQueue.write { db in
            try BackupFile.filter(ids.contains(Column("sessionId"))).deleteAll(db)
            try BackupSession.filter(ids.contains(Column("id"))).deleteAll(db)
            try cleanOrphanedDevices(db: db)
        }
    }
    
    func deleteAllSessions() throws {
        try dbQueue.write { db in
            try BackupFile.deleteAll(db)
            try BackupSession.deleteAll(db)
            try cleanOrphanedDevices(db: db)
        }
    }
    
    private func cleanOrphanedDevices(db: Database) throws {
        // Find devices that have no sessions and no files
        let devices = try BackupDevice.fetchAll(db)
        for device in devices {
            let sessionCount = try BackupSession.filter(Column("deviceSerial") == device.serial).fetchCount(db)
            let fileCount = try BackupFile.filter(Column("deviceSerial") == device.serial).fetchCount(db)
            
            if sessionCount == 0 && fileCount == 0 {
                try device.delete(db)
            }
        }
    }
    
    // MARK: - Application Settings
    func saveSetting(_ setting: ApplicationSetting) throws {
        try dbQueue.write { db in
            try setting.save(db)
        }
    }
    
    func getSetting(key: String) throws -> ApplicationSetting? {
        try dbQueue.read { db in
            try ApplicationSetting.fetchOne(db, key: key)
        }
    }
    
    func getAllSettings() throws -> [ApplicationSetting] {
        try dbQueue.read { db in
            try ApplicationSetting.fetchAll(db)
        }
    }
}
