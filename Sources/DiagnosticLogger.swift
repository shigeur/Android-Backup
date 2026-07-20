import Foundation
import SwiftUI

enum LogCategory: String, CaseIterable, Identifiable {
    case device = "Device"
    case transfer = "Transfer"
    case clipboard = "Clipboard"
    case filesystem = "Filesystem"
    case adb = "ADB"
    case directory = "Directory"
    case ui = "UI"
    case all = "All"
    
    var id: String { self.rawValue }
}

struct DiagnosticEvent: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let category: LogCategory
    
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

@MainActor
class DiagnosticLogger: ObservableObject {
    static let shared = DiagnosticLogger()
    
    @Published private(set) var events: [DiagnosticEvent] = []
    private let maxEvents = 200
    
    private init() {}
    
    func log(_ message: String, category: LogCategory) {
        let event = DiagnosticEvent(timestamp: Date(), message: message, category: category)
        events.append(event)
        
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }
    
    func clear() {
        events.removeAll()
    }
}
