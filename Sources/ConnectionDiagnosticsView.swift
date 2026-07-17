import SwiftUI

struct ConnectionDiagnosticsView: View {
    @ObservedObject var adbManager = ADBManager.shared
    
    // Diagnostic State
    @State private var adbExecutablePath = ""
    @State private var adbResolvedPath = ""
    @State private var adbExists = false
    @State private var adbIsExecutable = false
    @State private var adbIsReachable = false
    @State private var adbIsSymlink = false
    @State private var adbSymlinkTargetExists = false
    @State private var adbPosixPermissions = ""
    
    @State private var adbVersionRaw = ""
    @State private var adbVersionError = ""
    @State private var adbVersionDuration = 0
    
    @State private var adbServerStatusRaw = ""
    @State private var adbServerStatusError = ""
    @State private var adbServerDuration = 0
    
    @State private var adbDevicesRaw = ""
    @State private var adbDevicesError = ""
    @State private var adbDevicesDuration = 0
    
    @State private var parsedDevices: [String] = []
    
    @State private var testRunning = false
    
    var body: some View {
        VStack {
            HStack {
                Text("Connection Diagnostics")
                    .font(.title)
                    .bold()
                Spacer()
                Button(action: runTest) {
                    if testRunning {
                        ProgressView().controlSize(.small)
                        Text("Running Test...")
                    } else {
                        Image(systemName: "play.fill")
                        Text("Run Connection Test")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(testRunning)
            }
            .padding()
            
            Form {
                Section("1. ADB Executable") {
                    LabeledContent("Configured Path", value: adbExecutablePath)
                    LabeledContent("Resolved Path", value: adbResolvedPath)
                    LabeledContent("Is Symlink", value: adbIsSymlink ? "✅ Yes" : "❌ No")
                    if adbIsSymlink {
                        LabeledContent("Symlink Target Exists", value: adbSymlinkTargetExists ? "✅ Yes" : "❌ No")
                    }
                    LabeledContent("Exists (fileExists)", value: adbExists ? "✅ Yes" : "❌ No")
                    LabeledContent("Reachable (checkResourceIsReachable)", value: adbIsReachable ? "✅ Yes" : "❌ No")
                    LabeledContent("Is Executable", value: adbIsExecutable ? "✅ Yes" : "❌ No")
                    LabeledContent("POSIX Permissions", value: adbPosixPermissions)
                }
                
                Section("2. ADB Version") {
                    if !adbVersionError.isEmpty {
                        Text("❌ Error: \(adbVersionError)").foregroundColor(.red)
                    }
                    Text(adbVersionRaw.isEmpty ? "No output" : adbVersionRaw)
                        .font(.system(.body, design: .monospaced))
                    LabeledContent("Execution Time", value: "\(adbVersionDuration) ms")
                }
                
                Section("3. ADB Server Status (`adb get-state`)") {
                    if !adbServerStatusError.isEmpty {
                        Text("❌ Error: \(adbServerStatusError)").foregroundColor(.red)
                    }
                    Text(adbServerStatusRaw.isEmpty ? "No output" : adbServerStatusRaw)
                        .font(.system(.body, design: .monospaced))
                    LabeledContent("Execution Time", value: "\(adbServerDuration) ms")
                }
                
                Section("4. Device Discovery (`adb devices -l`)") {
                    if !adbDevicesError.isEmpty {
                        Text("❌ Error: \(adbDevicesError)").foregroundColor(.red)
                    }
                    Text(adbDevicesRaw.isEmpty ? "No output" : adbDevicesRaw)
                        .font(.system(.body, design: .monospaced))
                    LabeledContent("Execution Time", value: "\(adbDevicesDuration) ms")
                }
                
                Section("5. Parser Verification") {
                    if parsedDevices.isEmpty {
                        Text("0 Devices Parsed").foregroundColor(.secondary)
                    } else {
                        ForEach(parsedDevices, id: \.self) { device in
                            Text(device).font(.system(.body, design: .monospaced))
                        }
                    }
                }
                
                Section("6. UI Binding State") {
                    // We can check DeviceManager singleton here, but using EnvironmentObject is safer.
                    // For diagnostics, we'll just pull from ADBManager which doesn't hold device state,
                    // but we can query DeviceManager via a direct instance if needed, though 
                    // it is not a singleton by default. It's usually injected. 
                    // We'll leave UI Binding manual check up to the user seeing this window.
                    Text("Check main window for 'No device connected'. If parsed devices > 0 but main window is empty, UI Binding failed.")
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 600)
    }
    
    private func runTest() {
        testRunning = true
        
        // Clear previous state
        adbExecutablePath = adbManager.adbPath
        adbResolvedPath = ""
        adbExists = false
        adbIsExecutable = false
        adbIsReachable = false
        adbIsSymlink = false
        adbSymlinkTargetExists = false
        adbPosixPermissions = ""
        adbVersionRaw = ""
        adbVersionError = ""
        adbVersionDuration = 0
        adbServerStatusRaw = ""
        adbServerStatusError = ""
        adbServerDuration = 0
        adbDevicesRaw = ""
        adbDevicesError = ""
        adbDevicesDuration = 0
        parsedDevices = []
        
        Task {
            // 1. Check Executable
            adbExists = FileManager.default.fileExists(atPath: adbExecutablePath)
            adbIsExecutable = FileManager.default.isExecutableFile(atPath: adbExecutablePath)
            
            let url = URL(fileURLWithPath: adbExecutablePath)
            adbIsReachable = (try? url.checkResourceIsReachable()) ?? false
            adbResolvedPath = url.resolvingSymlinksInPath().path
            
            if let attrs = try? FileManager.default.attributesOfItem(atPath: adbExecutablePath) {
                let fileType = attrs[.type] as? FileAttributeType
                adbIsSymlink = (fileType == .typeSymbolicLink)
                if let posix = attrs[.posixPermissions] as? Int {
                    adbPosixPermissions = String(posix, radix: 8)
                }
            }
            
            if adbIsSymlink {
                adbSymlinkTargetExists = FileManager.default.fileExists(atPath: adbResolvedPath)
            }
            
            // 2. ADB Version
            do {
                let res = try await adbManager.runDetailed(["version"])
                adbVersionRaw = res.stdout + "\n" + res.stderr
                adbVersionDuration = res.durationMs
            } catch {
                adbVersionError = extractErrorDetails(error)
            }
            
            // 3. ADB Server
            do {
                let res = try await adbManager.runDetailed(["get-state"])
                adbServerStatusRaw = "State: \(res.stdout) \nExit Code: \(res.exitCode)\nStderr: \(res.stderr)"
                adbServerDuration = res.durationMs
            } catch {
                adbServerStatusError = extractErrorDetails(error)
            }
            
            // 4. ADB Devices
            do {
                let res = try await adbManager.runDetailed(["devices", "-l"])
                adbDevicesRaw = "Stdout:\n\(res.stdout)\n\nStderr:\n\(res.stderr)\nExit Code: \(res.exitCode)"
                adbDevicesDuration = res.durationMs
                
                // 5. Parser Test
                let lines = res.stdout.components(separatedBy: .newlines)
                for line in lines {
                    if line.starts(with: "List of devices") || line.trimmingCharacters(in: .whitespaces).isEmpty {
                        continue
                    }
                    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                    guard parts.count >= 2 else { continue }
                    
                    let serial = String(parts[0])
                    let status = String(parts[1])
                    var model = "Unknown Device"
                    for part in parts {
                        if part.starts(with: "model:") {
                            model = String(part.dropFirst("model:".count)).replacingOccurrences(of: "_", with: " ")
                        }
                    }
                    
                    parsedDevices.append("Serial: \(serial) | Status: \(status) | Model: \(model)")
                }
            } catch {
                adbDevicesError = extractErrorDetails(error)
            }
            
            testRunning = false
        }
    }
    
    private func extractErrorDetails(_ error: Error) -> String {
        let nsError = error as NSError
        var details = """
        Domain: \(nsError.domain)
        Code: \(nsError.code)
        Localized: \(nsError.localizedDescription)
        FailureReason: \(nsError.localizedFailureReason ?? "nil")
        RecoverySuggestion: \(nsError.localizedRecoverySuggestion ?? "nil")
        """
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] {
            details += "\nUnderlyingError: \(String(describing: underlying))"
        }
        return details
    }
}
