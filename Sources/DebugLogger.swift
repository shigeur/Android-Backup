import Foundation
import SwiftUI

struct ADBLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let directory: String
    let command: String
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let executionTimeMs: Int
    let filesParsed: Int?
    let viewModelRows: Int?
}

@MainActor
class DebugLogger: ObservableObject {
    static let shared = DebugLogger()
    
    @Published var logs: [ADBLogEntry] = []
    
    // Specifically track the last operation for the console view
    @Published var lastDirectory: String = ""
    @Published var lastCommand: String = ""
    @Published var lastStdout: String = ""
    @Published var lastStderr: String = ""
    @Published var lastExitCode: Int32 = 0
    @Published var lastExecutionTimeMs: Int = 0
    @Published var lastFilesParsed: Int = 0
    @Published var lastViewModelRows: Int = 0
    @Published var lastIsLoading: Bool = false
    @Published var lastError: String = "none"
    
    func logOperation(directory: String, command: String, stdout: String, stderr: String, exitCode: Int32, executionTimeMs: Int, filesParsed: Int?) {
        let entry = ADBLogEntry(
            timestamp: Date(),
            directory: directory,
            command: command,
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode,
            executionTimeMs: executionTimeMs,
            filesParsed: filesParsed,
            viewModelRows: lastViewModelRows
        )
        
        // Keep last 50 logs
        if logs.count > 50 { logs.removeFirst() }
        logs.append(entry)
        
        self.lastDirectory = directory
        self.lastCommand = command
        self.lastStdout = stdout
        self.lastStderr = stderr
        self.lastExitCode = exitCode
        self.lastExecutionTimeMs = executionTimeMs
        if let parsed = filesParsed {
            self.lastFilesParsed = parsed
        }
    }
}
