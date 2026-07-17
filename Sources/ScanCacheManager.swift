import Foundation

struct ScanCacheEntry {
    let timestamp: Date
    let deviceSerial: String
    let path: String
    let files: [RemoteFile]
}

@globalActor
actor ScanCacheActor {
    static let shared = ScanCacheActor()
}

@ScanCacheActor
class ScanCacheManager {
    static let shared = ScanCacheManager()
    
    private var cache: [String: ScanCacheEntry] = [:] // Keyed by "\(deviceSerial):\(path)"
    
    private init() {}
    
    func getCachedFiles(deviceSerial: String, path: String) -> [RemoteFile]? {
        let key = "\(deviceSerial):\(path)"
        if let entry = cache[key] {
            // Optional: Expiration logic (e.g. valid for 1 hour)
            if Date().timeIntervalSince(entry.timestamp) < 3600 {
                return entry.files
            } else {
                cache.removeValue(forKey: key)
            }
        }
        return nil
    }
    
    func setCachedFiles(deviceSerial: String, path: String, files: [RemoteFile]) {
        let key = "\(deviceSerial):\(path)"
        let entry = ScanCacheEntry(timestamp: Date(), deviceSerial: deviceSerial, path: path, files: files)
        cache[key] = entry
    }
    
    func invalidateCache(deviceSerial: String, path: String) {
        let key = "\(deviceSerial):\(path)"
        cache.removeValue(forKey: key)
    }
    
    func invalidateAll() {
        cache.removeAll()
    }
}
