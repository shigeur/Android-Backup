import SwiftUI

struct SettingsView: View {
    @ObservedObject var adbManager = ADBManager.shared
    @ObservedObject var settings = SettingsManager.shared
    
    @State private var showingDebugConsole = false
    @State private var showingConnectionDiagnostics = false
    
    @State private var adbVersionString: String? = nil
    @State private var isExecutable: Bool = false
    @State private var deviceDetected: Bool = false
    
    private var adbSource: String {
        if adbManager.adbPath == settings.manualAdbPath && !settings.manualAdbPath.isEmpty {
            return "User Configured"
        } else if adbManager.adbPath.contains("/opt/homebrew") {
            return "Homebrew (Auto-detected)"
        } else if adbManager.adbPath.contains("Android/sdk") {
            return "Android SDK (Auto-detected)"
        } else if !adbManager.adbPath.isEmpty {
            return "System PATH (Auto-detected)"
        } else {
            return "Not Found"
        }
    }
    
    private var isAdbValid: Bool {
        return !adbManager.adbPath.isEmpty && isExecutable && adbVersionString != nil
    }
    
    var body: some View {
        ScrollView {
            Form {
                GroupBox("ADB Configuration") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Status:")
                                .frame(width: 100, alignment: .trailing)
                            if isAdbValid {
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            } else {
                                Label("Not Configured", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        HStack {
                            Text("Active Path:")
                                .frame(width: 100, alignment: .trailing)
                            TextField("e.g. /opt/homebrew/bin/adb", text: $settings.manualAdbPath)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: settings.manualAdbPath) { _ in
                                    Task { await adbManager.discoverADB() }
                                }
                        }
                        
                        if isAdbValid {
                            HStack {
                                Text("Source:")
                                    .frame(width: 100, alignment: .trailing)
                                Text(adbSource)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack(alignment: .top) {
                                Text("Version:")
                                    .frame(width: 100, alignment: .trailing)
                                Text(adbVersionString ?? "Unknown")
                                    .foregroundColor(.secondary)
                                    .font(.system(.body, design: .monospaced))
                            }
                            
                            HStack {
                                Text("Validation:")
                                    .frame(width: 100, alignment: .trailing)
                                HStack(spacing: 12) {
                                    ValidationBadge(title: "File Exists", isValid: !adbManager.adbPath.isEmpty)
                                    ValidationBadge(title: "Executable", isValid: isExecutable)
                                    ValidationBadge(title: "Version OK", isValid: adbVersionString != nil)
                                    ValidationBadge(title: "Device", isValid: deviceDetected)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Android Platform Tools (ADB) is not installed or configured correctly.")
                                    .font(.headline)
                                Text("This application requires ADB to communicate with Android devices.")
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Button("Download Platform Tools") {
                                        if let url = URL(string: "https://developer.android.com/tools/releases/platform-tools") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    
                                    HelpButton {
                                        // Simple popover or instructions
                                    }
                                    .help("Installation Guide: Use 'brew install android-platform-tools' or download the official ZIP package and specify its path above.")
                                }
                                .padding(.top, 4)
                            }
                            .padding()
                            .background(Color(NSColor.windowBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                    .padding(8)
                }
                
                GroupBox("Developer Tools") {
                    HStack(spacing: 16) {
                        Button("Open Debug Console") {
                            showingDebugConsole = true
                        }
                        .help("View raw output from all executed ADB commands.")
                        
                        Button("Connection Diagnostics") {
                            showingConnectionDiagnostics = true
                        }
                        .help("Run a sequence of checks to verify device communication.")
                    }
                    .padding(8)
                }
                
                GroupBox("Transfer Settings") {
                    HStack {
                        Picker("Parallel Workers", selection: $settings.parallelWorkers) {
                            Text("1 (Safe/Sequential)").tag(1)
                            Text("2").tag(2)
                            Text("4").tag(4)
                            Text("8 (Fastest/High Load)").tag(8)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 400)
                        .help("Increase transfer performance by copying multiple files simultaneously. Higher values increase CPU and USB usage.")
                    }
                    .padding(8)
                    
                    Text("Using multiple workers can speed up small file transfers, but might overwhelm the Android storage if the device is slow.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                }
                
                GroupBox("Appearance") {
                    Toggle("Force Dark Mode", isOn: $settings.isDarkMode)
                        .padding(8)
                        .help("Override system appearance and force the application to use dark mode.")
                }
            }
            .padding(20)
        }
        .frame(minWidth: 600, minHeight: 500)
        .task(id: adbManager.adbPath) {
            await refreshAdbStatus()
        }
        .sheet(isPresented: $showingDebugConsole) {
            DebugConsoleView()
        }
        .sheet(isPresented: $showingConnectionDiagnostics) {
            ConnectionDiagnosticsView()
        }
    }
    
    private func refreshAdbStatus() async {
        isExecutable = FileManager.default.isExecutableFile(atPath: adbManager.adbPath)
        
        do {
            let versionOut = try await adbManager.run(["version"])
            adbVersionString = versionOut.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            adbVersionString = nil
        }
        
        do {
            let devicesOut = try await adbManager.run(["devices"])
            // format: "List of devices attached\n emulator-5554 device"
            let lines = devicesOut.components(separatedBy: .newlines)
            deviceDetected = lines.contains(where: { $0.contains("\tdevice") })
        } catch {
            deviceDetected = false
        }
        
        // Populate manual path if it was empty but adbManager auto-discovered one
        if settings.manualAdbPath.isEmpty && !adbManager.adbPath.isEmpty {
            settings.manualAdbPath = adbManager.adbPath
        }
    }
}

struct ValidationBadge: View {
    let title: String
    let isValid: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isValid ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(isValid ? .green : .red)
            Text(title)
                .font(.caption)
                .foregroundColor(isValid ? .primary : .secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(6)
    }
}

struct HelpButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark.circle")
                .foregroundColor(.blue)
        }
        .buttonStyle(.plain)
    }
}
