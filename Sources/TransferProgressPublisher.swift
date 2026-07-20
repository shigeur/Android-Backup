import Foundation
import SwiftUI
import Combine

@MainActor
class TransferProgressPublisher: ObservableObject {
    public static let shared = TransferProgressPublisher()
    
    @Published public var activeSessions: [String: TransferSession] = [:]
    
    private init() {}
    
    func createSession(device: AndroidDevice?, direction: TransferDirection?, destination: URL, isBackup: Bool, sessionID: String? = nil) -> TransferSession {
        let session = TransferSession(id: sessionID ?? UUID().uuidString.prefix(8).uppercased(), device: device, direction: direction, destination: destination, isBackup: isBackup)
        activeSessions[session.id] = session
        return session
    }
    
    func getSession(id: String) -> TransferSession? {
        return activeSessions[id]
    }
    
    func removeSession(id: String) {
        if let session = activeSessions[id] {
            session.cleanup()
        }
        activeSessions.removeValue(forKey: id)
    }
}
