import Foundation

@globalActor
actor CacheActor {
    static let shared = CacheActor()
}

@CacheActor
class DirectoryCache {
    static let shared = DirectoryCache()
    
    // Caches mapping path -> files
    private var androidCache: [String: [ADBFile]] = [:]
    private var macCache: [String: [LocalFileItem]] = [:]
    
    private init() {}
    
    // MARK: - Android Cache
    func getAndroidCache(for path: String) -> [ADBFile]? {
        return androidCache[path]
    }
    
    func setAndroidCache(for path: String, files: [ADBFile]) {
        androidCache[path] = files
    }
    
    func invalidateAndroidCache(for path: String) {
        androidCache.removeValue(forKey: path)
    }
    
    func invalidateAllAndroid() {
        androidCache.removeAll()
    }
    
    // MARK: - Mac Cache
    func getMacCache(for path: String) -> [LocalFileItem]? {
        return macCache[path]
    }
    
    func setMacCache(for path: String, files: [LocalFileItem]) {
        macCache[path] = files
    }
    
    func invalidateMacCache(for path: String) {
        macCache.removeValue(forKey: path)
    }
    
    func invalidateAllMac() {
        macCache.removeAll()
    }
    
    // Invalidate everything (e.g. on device disconnect)
    func invalidateAll() {
        invalidateAllAndroid()
        invalidateAllMac()
    }
}
