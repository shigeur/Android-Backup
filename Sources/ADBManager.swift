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
    
    /// Gets a list of currently connected Android devices
    func getConnectedDevices() async throws -> [AndroidDevice] {
        let output = try await run(["devices", "-l"])
        var devices: [AndroidDevice] = []
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            if line.hasPrefix("List of devices") { continue }
            
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if components.count >= 2 {
                let serial = components[0]
                let status = components[1]
                
                var model = "Unknown Device"
                for component in components {
                    if component.hasPrefix("model:") {
                        model = String(component.dropFirst(6)).replacingOccurrences(of: "_", with: " ")
                    }
                }
                
                devices.append(AndroidDevice(serial: serial, model: model, status: status))
            }
        }
        return devices
    }
    
    /// Executes an ADB command and returns detailed output without throwing on non-zero exit codes.
    func runDetailed(_ arguments: [String]) async throws -> (stdout: String, stderr: String, exitCode: Int32, durationMs: Int) {
        guard FileManager.default.fileExists(atPath: adbPath) else {
            throw ADBError.executableNotFound
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: adbPath)
        process.arguments = arguments
        
        return try await withTaskCancellationHandler {
            return try await withCheckedThrowingContinuation { continuation in
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                let inputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                process.standardInput = inputPipe
                
                let startTime = Date()
                let commandStr = "adb " + arguments.joined(separator: " ")
                
                // --- Install ALL handlers BEFORE process.run() ---
                
                let outputLock = NSLock()
                var outputData = Data()
                var errorData = Data()
                
                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty {
                        outputLock.lock()
                        outputData.append(data)
                        outputLock.unlock()
                    }
                }
                
                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty {
                        outputLock.lock()
                        errorData.append(data)
                        outputLock.unlock()
                    }
                }
                
                process.terminationHandler = { p in
                    // Allow a brief moment for final readabilityHandler callbacks to drain
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.05) {
                        outputPipe.fileHandleForReading.readabilityHandler = nil
                        errorPipe.fileHandleForReading.readabilityHandler = nil
                        
                        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)
                        
                        outputLock.lock()
                        let finalOutput = outputData
                        let finalError = errorData
                        outputLock.unlock()
                        
                        let outputStr = String(decoding: finalOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        let errorStr = String(decoding: finalError, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        
                        Task { @MainActor in
                            DebugLogger.shared.logOperation(
                                directory: "ADB",
                                command: commandStr,
                                stdout: outputStr,
                                stderr: errorStr,
                                exitCode: p.terminationStatus,
                                executionTimeMs: durationMs,
                                filesParsed: nil
                            )
                            TransferTrace.logADB(command: commandStr, stdout: outputStr, stderr: errorStr, exitCode: p.terminationStatus, durationMs: durationMs)
                        }
                        
                        if Task.isCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(returning: (stdout: outputStr, stderr: errorStr, exitCode: p.terminationStatus, durationMs: durationMs))
                        }
                    }
                }
                
                // --- NOW launch the process, after all handlers are installed ---
                do {
                    try process.run()
                } catch {
                    // Clean up handlers since process never started
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }
    
    /// Executes an ADB command and streams standard output line by line.
    func runStreaming(_ arguments: [String]) -> AsyncStream<String> {
        return AsyncStream { continuation in
            guard FileManager.default.fileExists(atPath: adbPath) else {
                continuation.finish()
                return
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: adbPath)
            process.arguments = arguments
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            
            // Do not capture standard error for this stream to avoid interweaving,
            // or we could capture it separately if needed.
            
            let fileHandle = outputPipe.fileHandleForReading
            
            var buffer = Data()
            
            fileHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    return
                }
                buffer.append(data)
                
                // Extract lines
                var range = buffer.range(of: Data("\n".utf8))
                while let r = range {
                    let lineData = buffer.subdata(in: 0..<r.lowerBound)
                    if let lineStr = String(data: lineData, encoding: .utf8) {
                        continuation.yield(lineStr)
                    }
                    buffer.removeSubrange(0..<r.upperBound)
                    range = buffer.range(of: Data("\n".utf8))
                }
            }
            
            process.terminationHandler = { _ in
                fileHandle.readabilityHandler = nil
                
                // Flush remaining buffer
                if !buffer.isEmpty {
                    if let lineStr = String(data: buffer, encoding: .utf8) {
                        continuation.yield(lineStr)
                    }
                }
                continuation.finish()
            }
            
            do {
                try process.run()
                
                continuation.onTermination = { @Sendable _ in
                    if process.isRunning {
                        process.terminate()
                    }
                }
            } catch {
                continuation.finish()
            }
        }
    }
}
