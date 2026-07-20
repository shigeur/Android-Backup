import Foundation
import SwiftUI

enum ActivePane: String {
    case android = "Android Pane"
    case mac = "Mac Pane"
    case none = "None"
}

@MainActor
class UIStateManager: ObservableObject {
    static let shared = UIStateManager()
    
    @Published var focusedPane: ActivePane = .none
    
    private init() {}
}
