import Foundation
import Combine

enum ADBError: Error, LocalizedError {
    case executableNotFound
    case executionFailed(exitCode: Int32, output: String)
    case timeout
    case parsingError(String)
    
    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "ADB executable not found. Please specify the path in Settings."
        case .executionFailed(let code, let output):
            return "ADB command failed (code \(code)): \(output)"
        case .timeout:
            return "ADB command timed out."
        case .parsingError(let msg):
            return "Failed to parse ADB output: \(msg)"
        }
    }
}

class ADBManager: ObservableObject {
    @Published var adbPath: String = ""
    
    static let shared = ADBManager()
    
    private init() { }
    
    @MainActor
    func discoverADB() async -> Bool {
        // 1. Check if we have a manual path
        if let manual = UserDefaults.standard.string(forKey: "manualAdbPath"), !manual.isEmpty {
            adbPath = manual
            if await validateADB() { return true }
        }
        
        // 3. Search common locations
        let commonPaths = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            "/usr/bin/adb"
        ]
        
        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                adbPath = path
                if await validateADB() { return true }
            }
        }
        
        // 4. Try Android SDK path
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            let androidPath = home + "/Library/Android/sdk/platform-tools/adb"
            if FileManager.default.fileExists(atPath: androidPath) {
                adbPath = androidPath
                if await validateADB() { return true }
            }
        }
        
        // 5. Try 'which adb' via shell
        if let whichPath = await runWhichADB() {
            adbPath = whichPath
            if await validateADB() { return true }
        }
        
        return false
    }
    
    private func validateADB() async -> Bool {
        guard FileManager.default.isExecutableFile(atPath: adbPath) else { return false }
        do {
            let output = try await runDetailed(["version"])
            return output.exitCode == 0 && output.stdout.contains("Android Debug Bridge")
        } catch {
            return false
        }
    }
    
    private func runWhichADB() async -> String? {
        do {
            return try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/sh")
                process.arguments = ["-c", "which adb"]
                let pipe = Pipe()
                process.standardOutput = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    if process.terminationStatus == 0 {
                        let data = try pipe.fileHandleForReading.readToEnd()
                        let path = (data != nil) ? String(decoding: data!, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                        continuation.resume(returning: path.isEmpty ? nil : path)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        } catch {
            return nil
        }
    }
    
    /// Executes a simple ADB command and returns the standard output. Throws if exit code != 0.
    func run(_ arguments: [String]) async throws -> String {
        let result = try await runDetailed(arguments)
        if result.exitCode == 0 {
            return result.stdout
        } else {
            throw ADBError.executionFailed(exitCode: result.exitCode, output: result.stdout + "\n" + result.stderr)
        }
    }
    
    /// Executes an ADB command and returns detailed output without throwing on non-zero exit codes.
    func runDetailed(_ arguments: [String]) async throws -> (stdout: String, stderr: String, exitCode: Int32, durationMs: Int) {
        guard FileManager.default.fileExists(atPath: adbPath) else {
            throw ADBError.executableNotFound
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adbPath)
            process.arguments = arguments
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            let startTime = Date()
            
            do {
                try process.run()
                
                let outputData = try outputPipe.fileHandleForReading.readToEnd()
                let errorData = try errorPipe.fileHandleForReading.readToEnd()
                
                process.waitUntilExit()
                
                let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
                
                let outputStr = (outputData != nil) ? String(decoding: outputData!, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                let errorStr = (errorData != nil) ? String(decoding: errorData!, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                
                let commandStr = "adb " + arguments.joined(separator: " ")
                
                Task { @MainActor in
                    DebugLogger.shared.logOperation(
                        directory: "ADB",
                        command: commandStr,
                        stdout: outputStr,
                        stderr: errorStr,
                        exitCode: process.terminationStatus,
                        executionTimeMs: durationMs,
                        filesParsed: nil
                    )
                }
                
                continuation.resume(returning: (stdout: outputStr, stderr: errorStr, exitCode: process.terminationStatus, durationMs: durationMs))
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
