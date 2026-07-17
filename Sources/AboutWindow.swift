import SwiftUI
import AppKit

struct AboutWindow: View {
    @Environment(\.dismiss) private var dismiss
    
    // Live System Info State
    @State private var adbVersion: String = "Detecting..."
    @State private var adbExecutable: String = "Detecting..."
    @State private var connectedDevices: String = "Detecting..."
    
    // Static Information
    private let macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
    
    private var cpuArchitecture: String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) { bufPtr -> String in
            let data = Data(bufPtr)
            if let string = String(data: data, encoding: .utf8) {
                return string.trimmingCharacters(in: .controlCharacters)
            }
            return "Unknown"
        }
        return machine
    }
    
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Beta-1 Stable"
    private let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    private let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.unknown.AndroidBackup"
    private let appLocation = Bundle.main.bundlePath
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                
                // HEADER
                HStack(alignment: .top, spacing: 20) {
                    Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 128, height: 128)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Android Backup")
                            .font(.system(size: 28, weight: .bold))
                        
                        Text("Version \(appVersion) (Build \(buildNumber))")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                        
                        Text("Fast Android Backup for macOS")
                            .font(.system(size: 14, weight: .medium))
                            .padding(.top, 4)
                    }
                }
                
                // APPLICATION DESCRIPTION
                GroupBox("About") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Android Backup is an open-source macOS application created to make transferring files between Android devices and macOS significantly faster, easier, and more reliable.")
                        
                        Text("The project was created because Android's standard MTP (Media Transfer Protocol) performs poorly when transferring large numbers of small files. Typical examples include:")
                        
                        HStack(alignment: .top, spacing: 32) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• Camera Photos")
                                Text("• Camera Videos")
                                Text("• Screenshots")
                                Text("• WhatsApp Images")
                                Text("• WhatsApp Videos")
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• WhatsApp Documents")
                                Text("• Telegram Media")
                                Text("• Downloads")
                                Text("• Voice Notes")
                                Text("• Documents")
                            }
                        }
                        .foregroundColor(.secondary)
                        
                        Text("Copying these folders over MTP is often extremely slow because each file requires individual MTP operations.")
                        
                        Text("Android Backup solves this problem by using Android Debug Bridge (ADB) whenever possible, allowing dramatically faster and more reliable transfers.")
                        
                        Text("The project aims to provide a native macOS experience while maintaining compatibility with standard Android devices.")
                    }
                    .font(.body)
                    .padding(8)
                }
                
                // FEATURES
                GroupBox("Features") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
                        FeatureRow("Native macOS Interface")
                        FeatureRow("ADB Accelerated Transfers")
                        FeatureRow("Backup Mode")
                        FeatureRow("Dual Pane File Manager")
                        FeatureRow("Drag & Drop")
                        FeatureRow("Keyboard Shortcuts")
                        FeatureRow("Duplicate Detection")
                        FeatureRow("Parallel Copy Engine")
                        FeatureRow("Progress Tracking")
                        FeatureRow("File Verification")
                        FeatureRow("Native AppKit File Browser")
                    }
                    .padding(8)
                }
                
                // PROJECT INFORMATION
                GroupBox("Project Information") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Text("Project Name:").foregroundColor(.secondary)
                            Text("Android Backup")
                        }
                        GridRow {
                            Text("Developer:").foregroundColor(.secondary)
                            Text("Ninos")
                        }
                        GridRow {
                            Text("Project Type:").foregroundColor(.secondary)
                            Text("Open Source")
                        }
                        GridRow {
                            Text("License:").foregroundColor(.secondary)
                            Text("MIT License")
                        }
                        GridRow {
                            Text("Development:").foregroundColor(.secondary)
                            Text("Developed by Ninos.\nDevelopment assisted by Google Antigravity AI.")
                        }
                        GridRow {
                            Text("Technology:").foregroundColor(.secondary)
                            Text("Swift, SwiftUI, AppKit, SQLite (GRDB), Android Platform Tools (ADB)")
                        }
                    }
                    .padding(8)
                    .font(.system(size: 13))
                }
                
                // LIVE SYSTEM INFORMATION
                GroupBox("Live System Information") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        GridRow {
                            Text("macOS Version:").foregroundColor(.secondary)
                            Text(macOSVersion)
                        }
                        GridRow {
                            Text("CPU Architecture:").foregroundColor(.secondary)
                            Text(cpuArchitecture)
                        }
                        GridRow {
                            Text("Bundle Identifier:").foregroundColor(.secondary)
                            Text(bundleIdentifier)
                        }
                        GridRow {
                            Text("Application Location:").foregroundColor(.secondary)
                            Text(appLocation)
                        }
                        GridRow {
                            Text("ADB Executable:").foregroundColor(.secondary)
                            Text(adbExecutable)
                        }
                        GridRow {
                            Text("ADB Version:").foregroundColor(.secondary)
                            Text(adbVersion).lineLimit(1).truncationMode(.tail)
                        }
                        GridRow {
                            Text("Detected Devices:").foregroundColor(.secondary)
                            Text(connectedDevices)
                        }
                    }
                    .padding(8)
                    .font(.system(size: 13))
                }
                
                // PROJECT MISSION
                GroupBox("Project Mission") {
                    Text("\"Our mission is to give Android users a fast, reliable, and truly native backup experience on macOS without the limitations of traditional MTP.\"")
                        .font(.body)
                        .italic()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(8)
                }
                
                // ROADMAP
                GroupBox("Planned Features") {
                    HStack(alignment: .top, spacing: 32) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Incremental Backup")
                            Text("• Restore Wizard")
                            Text("• Folder Synchronization")
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Search")
                            Text("• Backup Profiles")
                            Text("• Scheduled Backup")
                        }
                    }
                    .foregroundColor(.secondary)
                    .padding(8)
                }
                
                // SUPPORT
                GroupBox("Support") {
                    HStack(spacing: 16) {
                        Button("GitHub Repository") { }
                            .disabled(true)
                        Button("Website") { }
                            .disabled(true)
                        Button("Documentation") { }
                            .disabled(true)
                        Button("Issue Tracker") { }
                            .disabled(true)
                    }
                    .padding(8)
                }
                
                Divider()
                
                Text("Made for Android users who want fast, reliable, and native backups on macOS.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                
                HStack {
                    Button("Copy System Information") {
                        copySystemInformation()
                    }
                    
                    Spacer()
                    
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding(.top, 16)
            }
            .padding(30)
        }
        .frame(width: 700, height: 650)
        .background(Color(NSColor.windowBackgroundColor))
        // Bind Cmd+W as well
        .background(
            Button("") {
                dismiss()
            }
            .keyboardShortcut("w", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        )
        .task {
            await loadLiveInformation()
        }
    }
    
    private func loadLiveInformation() async {
        let adbManager = ADBManager.shared
        
        adbExecutable = adbManager.adbPath.isEmpty ? "Not configured" : adbManager.adbPath
        
        if !adbManager.adbPath.isEmpty {
            do {
                let v = try await adbManager.run(["version"])
                adbVersion = v.components(separatedBy: .newlines).first ?? "Unknown"
            } catch {
                adbVersion = "Error fetching version"
            }
            
            do {
                let d = try await adbManager.run(["devices", "-l"])
                let lines = d.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.starts(with: "List of devices") }
                if lines.isEmpty {
                    connectedDevices = "0 devices"
                } else {
                    connectedDevices = "\(lines.count) device(s) (\(lines.map { $0.components(separatedBy: " ").first ?? "unknown" }.joined(separator: ", ")))"
                }
            } catch {
                connectedDevices = "Error fetching devices"
            }
        }
    }
    
    private func copySystemInformation() {
        let report = """
        Android Backup \(appVersion)
        Build \(buildNumber)
        
        macOS: \(macOSVersion)
        Architecture: \(cpuArchitecture)
        
        ADB Version: \(adbVersion)
        ADB Path: \(adbExecutable)
        Connected Devices: \(connectedDevices)
        
        Bundle Identifier: \(bundleIdentifier)
        Application Location: \(appLocation)
        """
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(report, forType: .string)
    }
}

struct FeatureRow: View {
    let title: String
    
    init(_ title: String) {
        self.title = title
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.blue)
            Text(title)
        }
    }
}
