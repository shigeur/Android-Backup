import SwiftUI
import UniformTypeIdentifiers

struct DualPaneView: View {
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var transferService = TransferService.shared
    @ObservedObject var fileOperationService = FileOperationService.shared
    
    @StateObject private var androidViewModel: DirectoryViewModel
    @StateObject private var localViewModel = LocalDirectoryViewModel()
    enum Pane {
        case android
        case mac
    }
    
    @State private var showSmartSync = false
    @FocusState private var activePane: Pane?
    
    init() {
        self.deviceManager = DeviceManager.shared
        let device = DeviceManager.shared.selectedDevice! // Guaranteed by coordinator
        _androidViewModel = StateObject(wrappedValue: DirectoryViewModel(device: device))
    }
    
    var body: some View {
        if deviceManager.selectedDevice != nil {
            ZStack {
                VStack(spacing: 0) {
                    HSplitView {
                        // Left pane: Android ADB
                        FileManagerView(deviceManager: deviceManager, viewModel: androidViewModel)
                            .focused($activePane, equals: .android)
                            .onTapGesture { activePane = .android }
                            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                            .onDrop(of: [UTType.fileURL, UTType.androidFile], isTargeted: nil) { providers in
                                guard let device = deviceManager.selectedDevice else { return false }
                                let destPath = androidViewModel.currentPath
                                let destURL = URL(fileURLWithPath: destPath)
                                var handled = false
                                
                                for provider in providers {
                                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                                        // Mac to Android
                                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                                            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                                Task {
                                                    await transferService.prepareTransfer(device: device, direction: .macToAndroid, sourcePaths: [url.path], destination: destURL, isBackup: false)
                                                }
                                            }
                                        }
                                        handled = true
                                    } else if provider.hasItemConformingToTypeIdentifier(UTType.androidFile.identifier) {
                                        // Android to Android
                                        // FileOperationService.shared.moveAndroidFiles(...)
                                        handled = true
                                    }
                                }
                                return handled
                            }
                        
                        // Right pane: macOS Local
                        LocalFileManagerView(viewModel: localViewModel)
                            .focused($activePane, equals: .mac)
                            .onTapGesture { activePane = .mac }
                            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                            .onDrop(of: [UTType.fileURL, UTType.androidFile], isTargeted: nil) { providers in
                                guard let device = deviceManager.selectedDevice, let destURL = localViewModel.currentURL else { return false }
                                var handled = false
                                
                                for provider in providers {
                                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                                        // Mac to Mac
                                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                                            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                                Task { await FileOperationService.shared.duplicateMacFiles(urls: [url]) }
                                            }
                                        }
                                        handled = true
                                    } else if provider.hasItemConformingToTypeIdentifier(UTType.androidFile.identifier) {
                                        // Android to Mac
                                        provider.loadItem(forTypeIdentifier: UTType.androidFile.identifier, options: nil) { (item, error) in
                                            if let data = item as? Data, let path = String(data: data, encoding: .utf8) {
                                                Task {
                                                    await transferService.prepareTransfer(device: device, direction: .androidToMac, sourcePaths: [path], destination: destURL, isBackup: false)
                                                }
                                            }
                                        }
                                        handled = true
                                    }
                                }
                                return handled
                            }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                    Divider()
                    
                    // Bottom Action Bar
                    HStack(spacing: 20) {
                        Spacer()
                        
                        Button(action: copyToAndroid) {
                            Label("Copy", systemImage: "arrow.left")
                        }
                        .disabled(localViewModel.selectedFileIDs.isEmpty)
                        
                        Button(action: copyToMac) {
                            Label("Copy", systemImage: "arrow.right")
                        }
                        .disabled(androidViewModel.selectedFileIDs.isEmpty)
                        
                        Button(action: { showSmartSync = true }) {
                            Label("Smart Sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(localViewModel.currentURL == nil || androidViewModel.currentPath == "/")
                        
                        Button(action: { /* Delete */ }) {
                            Label("Delete", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                        
                        Button(action: { /* Verify */ }) {
                            Label("Verify", systemImage: "checkmark.circle")
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .background(Color(NSColor.windowBackgroundColor))
                }
                
                if transferService.state != .idle {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    TransferProgressView {
                        // On dismiss, refresh panes
                        androidViewModel.loadDirectory(androidViewModel.currentPath)
                        if let currentURL = localViewModel.currentURL {
                            localViewModel.loadDirectory(currentURL)
                        }
                    }
                } else if fileOperationService.isOperating || fileOperationService.error != nil {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    VStack(spacing: 20) {
                        if let error = fileOperationService.error {
                            Image(systemName: "xmark.octagon.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.red)
                            Text("Operation Failed")
                                .font(.headline)
                            Text(error)
                                .foregroundColor(.secondary)
                            Button("Close") {
                                fileOperationService.error = nil
                            }
                        } else {
                            Text(fileOperationService.operationDescription)
                                .font(.headline)
                            ProgressView(value: fileOperationService.operationProgress)
                                .progressViewStyle(.linear)
                            Text("\(Int(fileOperationService.operationProgress * 100))%")
                        }
                    }
                    .padding()
                    .frame(width: 300)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(10)
                    .shadow(radius: 10)
                }
            }
            .sheet(isPresented: $showSmartSync) {
                if let localURL = localViewModel.currentURL {
                    SmartSyncView(
                        device: deviceManager.selectedDevice!,
                        localURL: localURL,
                        remotePath: androidViewModel.currentPath,
                        isPresented: $showSmartSync
                    )
                }
            }
        } else {
            Text("No device connected")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func copyToMac() {
        guard let device = deviceManager.selectedDevice else { return }
        let selectedFiles = androidViewModel.files.filter { androidViewModel.selectedFileIDs.contains($0.id) }
        guard !selectedFiles.isEmpty else { return }
        
        let sourcePaths = selectedFiles.map { $0.path }
        guard let dest = localViewModel.currentURL else { return }
        
        Task {
            await transferService.prepareTransfer(
                device: device,
                direction: .androidToMac,
                sourcePaths: sourcePaths,
                destination: dest,
                isBackup: false
            )
        }
    }
    
    private func copyToAndroid() {
        guard let device = deviceManager.selectedDevice else { return }
        let selectedFiles = localViewModel.files.filter { localViewModel.selectedFileIDs.contains($0.id) }
        guard !selectedFiles.isEmpty else { return }
        
        let sourcePaths = selectedFiles.map { $0.url.path }
        let dest = androidViewModel.currentPath
        
        // TransferService expects the destination to be passed as a URL even for MacToAndroid (it extracts the path)
        let destURL = URL(fileURLWithPath: dest)
        
        Task {
            await transferService.prepareTransfer(
                device: device,
                direction: .macToAndroid,
                sourcePaths: sourcePaths,
                destination: destURL,
                isBackup: false
            )
        }
    }
    
    private func performGlobalPaste() {
        guard let item = ClipboardService.shared.currentItem else { return }
        
        let destPane = activePane ?? (item.platform == .mac ? .android : .mac)
        
        if destPane == .android {
            if item.platform == .mac {
                guard let device = deviceManager.selectedDevice else { return }
                let destURL = URL(fileURLWithPath: androidViewModel.currentPath)
                Task {
                    await transferService.prepareTransfer(
                        device: device,
                        direction: .macToAndroid,
                        sourcePaths: item.paths,
                        destination: destURL,
                        isBackup: false
                    )
                }
            } else {
                // Android to Android Move/Copy is not yet implemented in TransferService
                // But could be delegated to FileOperationService if needed.
            }
        } else {
            if item.platform == .android {
                guard let device = deviceManager.selectedDevice, let dest = localViewModel.currentURL else { return }
                Task {
                    await transferService.prepareTransfer(
                        device: device,
                        direction: .androidToMac,
                        sourcePaths: item.paths,
                        destination: dest,
                        isBackup: false
                    )
                }
            } else {
                let urls = item.paths.map { URL(fileURLWithPath: $0) }
                Task { await FileOperationService.shared.duplicateMacFiles(urls: urls) }
            }
        }
        
        if item.action == .cut {
            ClipboardService.shared.clear()
        }
    }
}
