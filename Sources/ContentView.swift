import SwiftUI

struct ContentView: View {
    @StateObject private var coordinator = ApplicationStartupCoordinator.shared
    @State private var selectedTab: String? = "filemanager"
    
    var body: some View {
        Group {
            switch coordinator.state {
            case .launching, .initializingADB, .detectingDevices, .loadingInitialDirectory:
                LoadingStateView(state: coordinator.state)
            case .noDevice:
                EmptyDeviceView()
            case .error(let message):
                ErrorStateView(message: message)
            case .ready:
                NavigationSplitView {
                    List(selection: $selectedTab) {
                        NavigationLink("Devices", value: "devices")
                        NavigationLink("File Manager", value: "filemanager")
                        NavigationLink("Dual Pane", value: "dualpane")
                        NavigationLink("Backup", value: "backup")
                        NavigationLink("History", value: "history")
                        NavigationLink("Settings", value: "settings")
                    }
                    .navigationTitle("Android Backup")
                } detail: {
                    if selectedTab == "devices" {
                        if let device = DeviceManager.shared.selectedDevice {
                            DeviceInfoView(device: device)
                        } else {
                            EmptyDeviceView()
                        }
                    } else if selectedTab == "filemanager" {
                        StandaloneFileManagerView()
                    } else if selectedTab == "dualpane" {
                        DualPaneView()
                    } else if selectedTab == "backup" {
                        BackupView(deviceManager: DeviceManager.shared)
                    } else if selectedTab == "history" {
                        HistoryView()
                    } else if selectedTab == "settings" {
                        SettingsView()
                    } else {
                        Text("Select an item from the sidebar")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            coordinator.start()
        }
    }
}

struct LoadingStateView: View {
    let state: ApplicationState
    
    private var statusMessage: String {
        switch state {
        case .launching: return "Starting up..."
        case .initializingADB: return "Initializing Android Debug Bridge..."
        case .detectingDevices: return "Detecting Android devices..."
        case .loadingInitialDirectory: return "Loading initial directory..."
        default: return "Loading..."
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text(statusMessage)
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorStateView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundColor(.red)
            Text("Startup Error")
                .font(.title)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                ApplicationStartupCoordinator.shared.state = .launching
                ApplicationStartupCoordinator.shared.start()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyDeviceView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "candybarphone")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("No Android Device Connected")
                .font(.title2)
            Text("Please connect your device via USB and ensure USB Debugging is enabled.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DeviceInfoView: View {
    let device: AndroidDevice
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(device.model)
                .font(.largeTitle)
                .fontWeight(.bold)
            
            HStack(spacing: 30) {
                InfoBadge(title: "Android Version", value: device.androidVersion ?? "Unknown", icon: "candybarphone")
                InfoBadge(title: "Battery", value: device.batteryLevel != nil ? "\(device.batteryLevel!)%" : "Unknown", icon: "battery.100")
                InfoBadge(title: "Status", value: device.status.capitalized, icon: device.status == "device" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(device.status == "device" ? .green : .orange)
            }
            
            if let total = device.storageTotalBytes, let free = device.storageFreeBytes {
                let used = total - free
                VStack(alignment: .leading) {
                    Text("Storage")
                        .font(.headline)
                    ProgressView(value: Double(used), total: Double(total))
                        .tint(.blue)
                    HStack {
                        Text("\(formatBytes(used)) Used")
                        Spacer()
                        Text("\(formatBytes(free)) Available")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.top)
            }
            
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct InfoBadge: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline)
            }
        }
    }
}
