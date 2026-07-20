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
    @State private var currentProgress: TransferProgress? = nil
    
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
                        FileManagerView(deviceManager: deviceManager, viewModel: androidViewModel, onFocus: {
                            print("[DebugLogger] Focused pane changed to: Android via onFocus callback")
                            activePane = .android
                        })
                            .focused($activePane, equals: .android)
                            .onCommand(Selector("copy:")) {
                                ClipboardManager.shared.copy(paths: Array(androidViewModel.selectedFileIDs), platform: .android, deviceSerial: deviceManager.selectedDevice?.serial)
                            }
                            .onCommand(Selector("cut:")) {
                                ClipboardManager.shared.cut(paths: Array(androidViewModel.selectedFileIDs), platform: .android, deviceSerial: deviceManager.selectedDevice?.serial)
                            }
                            .onCommand(Selector("paste:")) {
                                let destPath = androidViewModel.currentPath
                                let destURL = URL(fileURLWithPath: destPath)
                                TransferEngine.shared.executePaste(destPlatform: .android, destPath: destPath, destURL: destURL, onProgress: handleProgress)
                            }
                            .onCommand(Selector("delete:")) {
                                NotificationCenter.default.post(name: Notification.Name("AndroidTriggerDelete"), object: nil)
                            }
                            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                            .onDrop(of: [UTType.fileURL, UTType.plainText], isTargeted: nil) { providers in
                                print("[DebugLogger] DualPaneView Android Pane received onDrop with \(providers.count) providers")
                                guard let device = deviceManager.selectedDevice else { return false }
                                let destPath = androidViewModel.currentPath
                                let destURL = URL(fileURLWithPath: destPath)
                                var handled = false
                                
                                for provider in providers {
                                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                                        print("[DebugLogger] DualPaneView Android Pane provider has fileURL")
                                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                                            print("[DebugLogger] DualPaneView Android Pane loadItem completed, error: \(String(describing: error))")
                                            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                                print("[DebugLogger] DualPaneView Android Pane loading url: \(url.path)")
                                                Task { @MainActor in
                                                    print("[DebugLogger] DualPaneView Android Pane executing transfer mac->android")
                                                    TransferEngine.shared.executeTransfer(action: .copy, sourcePlatform: .mac, sourceDeviceSerial: nil, sourcePaths: [url.path], destPlatform: .android, destPath: destPath, destURL: destURL, onProgress: handleProgress)
                                                }
                                            } else {
                                                print("[DebugLogger] DualPaneView Android Pane item is not Data or URL could not be parsed: \(String(describing: item))")
                                            }
                                        }
                                        handled = true
                                    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                                        print("[DebugLogger] DualPaneView Android Pane provider has plainText")
                                        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { (item, error) in
                                            print("[DebugLogger] DualPaneView Android Pane loadItem completed, error: \(String(describing: error))")
                                            var parsedPath: String?
                                            if let data = item as? Data, let str = String(data: data, encoding: .utf8) {
                                                parsedPath = str
                                            } else if let str = item as? String {
                                                parsedPath = str
                                            }
                                            
                                            if let pathStr = parsedPath, pathStr.hasPrefix("android://") {
                                                let path = String(pathStr.dropFirst("android://".count))
                                                print("[DebugLogger] DualPaneView Android Pane loading path: \(path)")
                                                Task { @MainActor in
                                                    print("[DebugLogger] DualPaneView Android Pane executing transfer android->android")
                                                    TransferEngine.shared.executeTransfer(action: .copy, sourcePlatform: .android, sourceDeviceSerial: device.serial, sourcePaths: [path], destPlatform: .android, destPath: destPath, destURL: destURL, onProgress: handleProgress)
                                                }
                                            } else {
                                                print("[DebugLogger] DualPaneView Android Pane item is not Data or path could not be parsed/has no prefix: \(String(describing: item))")
                                            }
                                        }
                                        handled = true
                                    }
                                }
                                return handled
                            }
                        
                        // Right pane: macOS Local
                        LocalFileManagerView(viewModel: localViewModel, onFocus: {
                            print("[DebugLogger] Focused pane changed to: Mac via onFocus callback")
                            activePane = .mac
                        })
                            .focused($activePane, equals: .mac)
                            .onCommand(Selector("copy:")) {
                                ClipboardManager.shared.copy(paths: Array(localViewModel.selectedFileIDs), platform: .mac)
                            }
                            .onCommand(Selector("cut:")) {
                                ClipboardManager.shared.cut(paths: Array(localViewModel.selectedFileIDs), platform: .mac)
                            }
                            .onCommand(Selector("paste:")) {
                                guard let destURL = localViewModel.currentURL else { return }
                                TransferEngine.shared.executePaste(destPlatform: .mac, destPath: destURL.path, destURL: destURL, onProgress: handleProgress)
                            }
                            .onCommand(Selector("delete:")) {
                                NotificationCenter.default.post(name: Notification.Name("MacTriggerDelete"), object: nil)
                            }
                            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                            .onDrop(of: [UTType.fileURL, UTType.plainText], isTargeted: nil) { providers in
                                print("[DebugLogger] DualPaneView Mac Pane received onDrop with \(providers.count) providers")
                                guard let device = deviceManager.selectedDevice, let destURL = localViewModel.currentURL else { return false }
                                var handled = false
                                
                                for provider in providers {
                                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                                        print("[DebugLogger] DualPaneView Mac Pane provider has fileURL")
                                        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (item, error) in
                                            print("[DebugLogger] DualPaneView Mac Pane loadItem completed, error: \(String(describing: error))")
                                            if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                                                print("[DebugLogger] DualPaneView Mac Pane loading url: \(url.path)")
                                                Task { @MainActor in
                                                    print("[DebugLogger] DualPaneView Mac Pane executing transfer mac->mac")
                                                    TransferEngine.shared.executeTransfer(action: .copy, sourcePlatform: .mac, sourceDeviceSerial: nil, sourcePaths: [url.path], destPlatform: .mac, destPath: destURL.path, destURL: destURL, onProgress: handleProgress)
                                                }
                                            } else {
                                                print("[DebugLogger] DualPaneView Mac Pane item is not Data or URL could not be parsed: \(String(describing: item))")
                                            }
                                        }
                                        handled = true
                                    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                                        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { (item, error) in
                                            var parsedPath: String?
                                            if let data = item as? Data, let str = String(data: data, encoding: .utf8) {
                                                parsedPath = str
                                            } else if let str = item as? String {
                                                parsedPath = str
                                            }
                                            if let pathStr = parsedPath, pathStr.hasPrefix("android://") {
                                                let path = String(pathStr.dropFirst("android://".count))
                                                Task { @MainActor in
                                                    TransferEngine.shared.executeTransfer(action: .copy, sourcePlatform: .android, sourceDeviceSerial: device.serial, sourcePaths: [path], destPlatform: .mac, destPath: destURL.path, destURL: destURL, onProgress: handleProgress)
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
            .onChange(of: activePane) { newValue in
                if newValue == .android {
                    UIStateManager.shared.focusedPane = .android
                    DiagnosticLogger.shared.log("Focused Pane: Android", category: .ui)
                } else if newValue == .mac {
                    UIStateManager.shared.focusedPane = .mac
                    DiagnosticLogger.shared.log("Focused Pane: Mac", category: .ui)
                } else {
                    UIStateManager.shared.focusedPane = .none
                    DiagnosticLogger.shared.log("Focused Pane: None", category: .ui)
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
                isBackup: false,
                duplicateMode: .fast,
                sessionID: nil,
                onProgress: handleProgress
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
                isBackup: false,
                duplicateMode: .fast,
                sessionID: nil,
                onProgress: handleProgress
            )
        }
    }
    
    private func performGlobalPaste() {
        if activePane == .android {
            TransferEngine.shared.executePaste(destPlatform: .android, destPath: androidViewModel.currentPath, destURL: URL(fileURLWithPath: androidViewModel.currentPath), onProgress: handleProgress)
        } else if let destURL = localViewModel.currentURL {
            TransferEngine.shared.executePaste(destPlatform: .mac, destPath: destURL.path, destURL: destURL, onProgress: handleProgress)
        }
    }
    
    private func handleProgress(_ progress: TransferProgress) {
        DispatchQueue.main.async {
            self.currentProgress = progress
            if progress.stage == .completed || progress.stage == .failed || progress.stage == .cancelled {
                // Clear after a delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if self.currentProgress?.sessionID == progress.sessionID {
                        self.currentProgress = nil
                    }
                }
            }
        }
    }
}
