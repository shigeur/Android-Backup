import Foundation

public enum TransferTrace {
    @TaskLocal public static var currentID: String?
    
    @MainActor
    public static func log(_ message: String) {
        if let id = currentID {
            DiagnosticLogger.shared.log("[Transfer \(id)]\n\(message)", category: .transfer)
        } else {
            // Fallback if no trace is active
            DiagnosticLogger.shared.log(message, category: .transfer)
        }
    }
    
    @MainActor
    public static func logADB(command: String, stdout: String, stderr: String, exitCode: Int32, durationMs: Int) {
        guard let id = currentID else { return }
        let msg = """
        [Transfer \(id)]
        ADB Process Started
        Command: \(command)
        Exit Code: \(exitCode)
        Execution Time: \(durationMs) ms
        stdout: \(stdout.prefix(500))
        stderr: \(stderr.prefix(500))
        """
        DiagnosticLogger.shared.log(msg, category: .adb)
    }
    
    @MainActor
    public static func logDirectory(requested: Bool = false, started: Bool = false, finished: Bool = false, itemCount: Int? = nil, durationMs: Int? = nil, path: String) {
        guard let id = currentID else { return }
        
        var msg = "[Transfer \(id)]\n"
        if requested {
            msg += "Directory Reload Requested: \(path)"
        } else if started {
            msg += "Directory Reload Started: \(path)"
        } else if finished {
            msg += "Directory Reload Finished: \(path)\nItem Count: \(itemCount ?? 0)\nDuration: \(durationMs ?? 0) ms"
        }
        DiagnosticLogger.shared.log(msg, category: .directory)
    }
    
    @MainActor
    public static func logFailure(reason: String, function: String, error: String, exitCode: Int32? = nil, durationMs: Int? = nil) {
        guard let id = currentID else { return }
        var msg = """
        [Transfer \(id)] FAILED
        Reason: \(reason)
        Function: \(function)
        Error: \(error)
        """
        if let exitCode = exitCode {
            msg += "\nExit Code: \(exitCode)"
        }
        if let durationMs = durationMs {
            msg += "\nDuration: \(durationMs) ms"
        }
        DiagnosticLogger.shared.log(msg, category: .transfer)
    }
    
    // Phase Timing
    @TaskLocal public static var phaseStartTimes: [String: Date]?
    
    @MainActor
    public static func logPhase(name: String, durationMs: Int) {
        guard let id = currentID else { return }
        DiagnosticLogger.shared.log("[Transfer \(id)] Phase Completed: \(name) - \(durationMs) ms", category: .transfer)
    }
}
