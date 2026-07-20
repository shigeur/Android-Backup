import SwiftUI

struct AndroidEmptyStateView: View {
    @StateObject private var lifecycle = DeviceLifecycleManager.shared
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        VStack(spacing: 30) {
            
            // Status Icon
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: iconName)
                    .font(.system(size: 64))
                    .foregroundColor(statusColor)
                    .opacity(isScanning ? 0.5 : 1.0)
                    .animation(isScanning ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: isScanning)
            }
            
            // Title and Status Indicator
            VStack(spacing: 8) {
                Text(titleText)
                    .font(.title)
                    .fontWeight(.bold)
                
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .opacity(isScanning ? 0.3 : 1.0)
                        .animation(isScanning ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: isScanning)
                    
                    Text(statusText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Refresh Button
            Button(action: {
                lifecycle.refreshManually()
            }) {
                HStack {
                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                        Text("Scanning...")
                    } else {
                        Image(systemName: "arrow.clockwise")
                        Text("Refresh Devices")
                    }
                }
                .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isScanning)
            
            // Troubleshooting Section
            troubleshootingSection
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .onAppear {
            print("[UI] Empty State Shown")
        }
        .onDisappear {
            print("[UI] Empty State Hidden")
        }
    }
    
    // MARK: - Computed Properties
    
    private var isScanning: Bool {
        lifecycle.state == .searching ||
        (String(describing: lifecycle.state).starts(with: "initializing"))
    }
    
    private var statusColor: Color {
        if isScanning { return .orange }
        switch lifecycle.state {
        case .idle, .disconnected: return .gray
        case .unauthorized: return .yellow
        case .adbMissing, .adbOffline, .error: return .red
        default: return .gray
        }
    }
    
    private var iconName: String {
        if isScanning { return "antenna.radiowaves.left.and.right" }
        switch lifecycle.state {
        case .idle, .disconnected: return "cable.connector"
        case .unauthorized: return "lock.shield"
        case .adbMissing: return "exclamationmark.triangle"
        case .adbOffline: return "wifi.exclamationmark"
        case .error: return "xmark.octagon"
        default: return "cable.connector"
        }
    }
    
    private var titleText: String {
        switch lifecycle.state {
        case .idle, .disconnected: return "No Android Device Connected"
        case .unauthorized: return "Authorization Required"
        case .adbMissing: return "Android Platform Tools Not Found"
        case .adbOffline: return "ADB Server Offline"
        case .error(_): return "Connection Error"
        default: return "Connecting..."
        }
    }
    
    private var statusText: String {
        if isScanning { return "Searching..." }
        switch lifecycle.state {
        case .idle, .disconnected: return "No Device"
        case .unauthorized: return "Unauthorized"
        case .adbMissing: return "ADB Missing"
        case .adbOffline: return "Server Offline"
        case .error: return "Error"
        default: return "Waiting"
        }
    }
    
    // MARK: - Troubleshooting View
    
    @ViewBuilder
    private var troubleshootingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if lifecycle.state == .adbMissing {
                Text("Android Platform Tools (ADB) is not installed or not found in your PATH.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Download Android Platform Tools") {
                    if let url = URL(string: "https://developer.android.com/tools/releases/platform-tools") {
                        openURL(url)
                    }
                }
                .buttonStyle(.link)
            } else if lifecycle.state == .unauthorized {
                Text("Your device is connected but USB Debugging authorization has not been accepted.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Text("Please unlock your Android phone and press **\"Allow\"**.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
            } else if lifecycle.state == .adbOffline {
                Text("ADB server is not responding.")
                    .foregroundColor(.secondary)
                
                Button("Restart ADB Server") {
                    Task {
                        _ = try? await ADBManager.shared.run(["kill-server"])
                        _ = try? await ADBManager.shared.run(["start-server"])
                        lifecycle.refreshManually()
                    }
                }
                .buttonStyle(.bordered)
            } else if lifecycle.state == .idle || lifecycle.state == .disconnected {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Things to check:")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    ChecklistItem(text: "USB cable is securely connected")
                    ChecklistItem(text: "USB Debugging is enabled in Developer Options")
                    ChecklistItem(text: "Allow USB debugging authorization on the device")
                    ChecklistItem(text: "Run `adb devices` in Terminal to verify")
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(8)
            } else if case .error(let msg) = lifecycle.state {
                Text(msg)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: 400)
    }
}

private struct ChecklistItem: View {
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(text)
                .foregroundColor(.secondary)
        }
    }
}
