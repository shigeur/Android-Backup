import Foundation
import GRDB

struct ApplicationSetting: Codable, FetchableRecord, PersistableRecord, Equatable {
    static let databaseTableName = "applicationSettings"
    
    var key: String
    var value: String
    var valueType: String
    var updatedAt: Date
}
