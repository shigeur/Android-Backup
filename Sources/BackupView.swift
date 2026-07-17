import SwiftUI

struct BackupView: View {
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var service = TransferService.shared    
    @State private var selectedFolders: Set<String> = ["/sdcard/DCIM", "/sdcard/Pictures"]
    @State private var destinationFolder: URL?
    
    let standardFolders = [
        "/sdcard/DCIM",
        "/sdcard/Pictures",
        "/sdcard/Movies",
        "/sdcard/Download",
        "/sdcard/Documents",
        "/sdcard/Music",
        "/sdcard/Android/media/com.whatsapp/WhatsApp/Media"
    ]
    
    init(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager
    }
    
    var body: some View {
        if deviceManager.selectedDevice == nil {
            Text("No device connected to backup.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                Text("Backup Options")
                    .font(.title)
                    .fontWeight(.bold)
                
                GroupBox(label: Text("Source Folders")) {
                    ScrollView {
                        VStack(alignment: .leading) {
                            ForEach(standardFolders, id: \.self) { folder in
                                Toggle(folder.replacingOccurrences(of: "/sdcard/", with: ""), isOn: Binding(
                                    get: { selectedFolders.contains(folder) },
                                    set: { isSelected in
                                        if isSelected {
                                            selectedFolders.insert(folder)
                                        } else {
                                            selectedFolders.remove(folder)
                                        }
                                    }
                                ))
                            }
                        }
                        .padding()
                    }
                    .frame(height: 150)
                }
                
                GroupBox(label: Text("Destination")) {
                    HStack {
                        Text(destinationFolder?.path ?? "No destination selected")
                            .foregroundColor(destinationFolder == nil ? .secondary : .primary)
                        Spacer()
                        Button("Choose...") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            if panel.runModal() == .OK {
                                destinationFolder = panel.url
                            }
                        }
                    }
                    .padding()
                }
                
                Spacer()
                
                // Progress Section
                if service.state != .idle {
                    TransferProgressView {
                        // On dismiss
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Button(action: startBackup) {
                        Text("Start Backup")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(destinationFolder == nil || selectedFolders.isEmpty)
                }
                
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
    
    private func startBackup() {
        guard let dest = destinationFolder, let device = deviceManager.selectedDevice else { return }
        Task {
            await service.prepareTransfer(device: device, direction: .androidToMac, sourcePaths: Array(selectedFolders), destination: dest, isBackup: true)
        }
    }
    
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useKB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytesPerSec)) + "/s"
    }
}
