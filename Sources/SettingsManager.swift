import Foundation
import Combine

@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    private let repository = BackupRepository.shared
    
    // In-memory cache to prevent constant DB reads on UI redraws
    private var cache: [String: String] = [:]
    
    private init() {}
    
    @Published var isDarkMode: Bool = false {
        didSet { save(key: "isDarkMode", value: isDarkMode) }
    }
    
    @Published var parallelWorkers: Int = 1 {
        didSet { save(key: "parallelWorkers", value: parallelWorkers) }
    }
    
    @Published var manualAdbPath: String = "" {
        didSet { save(key: "manualAdbPath", value: manualAdbPath) }
    }
    
    @Published var lastAndroidDeviceSerial: String = "" {
        didSet { save(key: "lastAndroidDeviceSerial", value: lastAndroidDeviceSerial) }
    }
    
    @Published var developerDebugEnabled: Bool = false {
        didSet { save(key: "developerDebugEnabled", value: developerDebugEnabled) }
    }
    
    /// Called once during ApplicationStartupCoordinator sequence
    func loadAllSettings() {
        do {
            let settings = try repository.getAllSettings()
            for setting in settings {
                cache[setting.key] = setting.value
            }
            
            // Hydrate properties from cache, or leave as default
            if let v = cache["isDarkMode"], let boolVal = Bool(v) { isDarkMode = boolVal }
            if let v = cache["parallelWorkers"], let intVal = Int(v) { parallelWorkers = intVal }
            if let v = cache["manualAdbPath"] { manualAdbPath = v }
            if let v = cache["lastAndroidDeviceSerial"] { lastAndroidDeviceSerial = v }
            if let v = cache["developerDebugEnabled"], let boolVal = Bool(v) { developerDebugEnabled = boolVal }
            
        } catch {
            print("Failed to load settings from database: \(error)")
        }
    }
    
    // MARK: - Internal DB sync
    
    private func save(key: String, value: Any) {
        let stringValue = "\(value)"
        let valueType = String(describing: type(of: value))
        
        cache[key] = stringValue
        
        let setting = ApplicationSetting(key: key, value: stringValue, valueType: valueType, updatedAt: Date())
        do {
            try repository.saveSetting(setting)
        } catch {
            print("Failed to save setting \(key) to DB: \(error)")
        }
    }
}
