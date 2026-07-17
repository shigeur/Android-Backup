import SwiftUI
import UniformTypeIdentifiers

struct FileManagerView: View {
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var viewModel: DirectoryViewModel
    
    @State private var showDeleteConfirmation = false
    @State private var itemsToDelete: [String] = []
    
    @State private var showRenamePrompt = false
    @State private var itemToRename: String? = nil
    @State private var newName: String = ""
    
    var breadcrumbs: [String] {
        let parts = viewModel.currentPath.split(separator: "/").map(String.init)
        var paths: [String] = []
        var current = ""
        for part in parts {
            current += "/" + part
            paths.append(current)
        }
        return paths.isEmpty ? ["/"] : paths
    }
    
    var body: some View {
        if deviceManager.selectedDevice != nil {
            VStack(spacing: 0) {
                // Toolbar/Breadcrumbs
                HStack {
                    Button(action: { viewModel.navigateUp() }) {
                        Image(systemName: "arrow.up")
                    }
                    .disabled(viewModel.currentPath == "/" || viewModel.currentPath == "")
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            Button("Root") {
                                viewModel.loadDirectory("/")
                            }
                            
                            ForEach(breadcrumbs, id: \.self) { path in
                                Text(">").foregroundColor(.secondary)
                                Button(URL(fileURLWithPath: path).lastPathComponent) {
                                    viewModel.loadDirectory(path)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Button(action: { viewModel.loadDirectory(viewModel.currentPath) }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                if let error = viewModel.error {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.red)
                        Text("Error Loading Directory")
                            .font(.title2)
                        Text(error)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            viewModel.loadDirectory(viewModel.currentPath)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HSplitView {
                        // Left Pane: Quick Access / Folder Tree placeholder
                        List {
                            Section("Quick Access") {
                                Button("Camera") { viewModel.loadDirectory("/sdcard/DCIM/Camera") }
                                Button("Downloads") { viewModel.loadDirectory("/sdcard/Download") }
                                Button("Movies") { viewModel.loadDirectory("/sdcard/Movies") }
                                Button("Music") { viewModel.loadDirectory("/sdcard/Music") }
                                Button("WhatsApp") { viewModel.loadDirectory("/sdcard/Android/media/com.whatsapp/WhatsApp/Media") }
                            }
                        }
                        .listStyle(.sidebar)
                        .frame(minWidth: 150, idealWidth: 200, maxWidth: 300, maxHeight: .infinity)
                        
                        NativeFileBrowser(items: viewModel.files, selection: $viewModel.selectedFileIDs, isLoading: viewModel.isLoading) { item in
                            if item.isDirectory {
                                viewModel.loadDirectory(item.path)
                            }
                        } contextMenuProvider: { selection in
                            return buildContextMenu(selection: selection)
                        }
                        // Menu is handled by NativeFileBrowser now
                        .frame(minWidth: 400, maxHeight: .infinity)
                        .background {
                            Group {
                                Button(action: { ClipboardService.shared.copy(paths: Array(viewModel.selectedFileIDs), platform: .android, deviceSerial: deviceManager.selectedDevice?.serial) }) { }
                                    .keyboardShortcut("c", modifiers: .command)
                                    
                                Button(action: { ClipboardService.shared.cut(paths: Array(viewModel.selectedFileIDs), platform: .android, deviceSerial: deviceManager.selectedDevice?.serial) }) { }
                                    .keyboardShortcut("x", modifiers: .command)
                                    
                                Button(action: { performPaste() }) { }
                                    .keyboardShortcut("v", modifiers: .command)
                                    
                                Button(action: { viewModel.selectedFileIDs = Set(viewModel.files.map { $0.id }) }) { }
                                    .keyboardShortcut("a", modifiers: .command)
                                    
                                Button(action: { triggerDelete(selection: viewModel.selectedFileIDs) }) { }
                                    .keyboardShortcut(.delete, modifiers: [])
                                    
                                Button(action: { triggerDelete(selection: viewModel.selectedFileIDs) }) { }
                                    .keyboardShortcut(.delete, modifiers: .command)
                                    
                                Button(action: { viewModel.loadDirectory(viewModel.currentPath) }) { }
                                    .keyboardShortcut("r", modifiers: .command)
                                    
                                Button(action: {
                                    if let first = viewModel.selectedFileIDs.first, viewModel.files.contains(where: { $0.id == first }) {
                                        // QuickLook
                                    }
                                }) { }
                                .keyboardShortcut(.space, modifiers: [])
                            }
                            .opacity(0)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    
                    Divider()
                    HStack {
                        Text("\(viewModel.files.count) Items")
                        
                        let totalSize = viewModel.files.reduce(0) { $0 + $1.size }
                        Text(formatBytes(totalSize))
                        
                        Spacer()
                        
                        if !viewModel.selectedFileIDs.isEmpty {
                            Text("Selected: \(viewModel.selectedFileIDs.count) Files")
                            
                            let selectedSize = viewModel.files.filter { viewModel.selectedFileIDs.contains($0.id) }.reduce(0) { $0 + $1.size }
                            Text(formatBytes(selectedSize))
                                .padding(.trailing, 10)
                        }
                        
                        if let device = deviceManager.selectedDevice {
                            Text("Device: \(device.model)")
                            Text(device.status == "device" ? "USB Connected" : device.status.capitalized)
                                .foregroundColor(device.status == "device" ? .green : .orange)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.windowBackgroundColor))
                    
                    // Loading handled in NativeFileBrowser
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                viewModel.loadDirectory(viewModel.currentPath)
            }
            .alert("Delete \(itemsToDelete.count) selected items?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let device = deviceManager.selectedDevice {
                        let paths = itemsToDelete
                        Task { await FileOperationService.shared.deleteAndroidFiles(device: device, paths: paths) }
                    }
                }
            } message: {
                Text("These files will be permanently removed from your Android device. This action cannot be undone.")
            }
            .alert("Rename File", isPresented: $showRenamePrompt) {
                TextField("New Name", text: $newName)
                Button("Cancel", role: .cancel) { }
                Button("Rename") {
                    if let device = deviceManager.selectedDevice, let path = itemToRename {
                        Task { await FileOperationService.shared.renameAndroidFile(device: device, path: path, newName: newName) }
                    }
                }
            } message: {
                Text("Enter a new name for this item.")
            }
        } else {
            Text("No device connected")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    private func triggerDelete(selection: Set<String>) {
        guard !selection.isEmpty else { return }
        itemsToDelete = Array(selection)
        showDeleteConfirmation = true
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func triggerRename(selection: Set<String>) {
        if let selectedID = selection.first, let file = viewModel.files.first(where: { $0.id == selectedID }) {
            itemToRename = file.path
            newName = file.name
            showRenamePrompt = true
        }
    }
    
    private func performPaste() {
        guard let item = ClipboardService.shared.currentItem, let device = deviceManager.selectedDevice else { return }
        let destURL = URL(fileURLWithPath: viewModel.currentPath)
        
        if item.platform == .mac {
            Task {
                await TransferService.shared.prepareTransfer(
                    device: device,
                    direction: .macToAndroid,
                    sourcePaths: item.paths,
                    destination: destURL,
                    isBackup: false
                )
            }
        } else {
            // Android to Android
        }
        
        if item.action == .cut { ClipboardService.shared.clear() }
    }
    
    private func iconForFile(_ file: ADBFile) -> String {
        if file.isDirectory { return "folder.fill" }
        switch file.extensionStr {
        case "jpg", "jpeg", "png", "heic", "webp": return "photo"
        case "mp4", "mkv", "avi", "mov": return "film"
        case "mp3", "m4a", "wav", "flac": return "music.note"
        case "pdf": return "doc.richtext"
        case "txt", "md": return "doc.text"
        case "zip", "rar", "7z", "tar", "gz": return "doc.zipper"
        case "apk": return "app.badge"
        default: return "doc"
        }
    }
    
    private func buildContextMenu(selection: Set<String>) -> NSMenu? {
        let menu = NSMenu()
        
        let openItem = ClosureMenuItem(title: "Open", keyEquivalent: "") {
            if let selectedID = selection.first,
               let file = self.viewModel.files.first(where: { $0.id == selectedID }),
               file.isDirectory {
                self.viewModel.loadDirectory(file.path)
            }
        }
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let copyItem = ClosureMenuItem(title: "Copy", keyEquivalent: "c") {
            ClipboardService.shared.copy(paths: Array(selection), platform: .android, deviceSerial: self.deviceManager.selectedDevice?.serial)
        }
        copyItem.isEnabled = !selection.isEmpty
        menu.addItem(copyItem)
        
        let cutItem = ClosureMenuItem(title: "Cut", keyEquivalent: "x") {
            ClipboardService.shared.cut(paths: Array(selection), platform: .android, deviceSerial: self.deviceManager.selectedDevice?.serial)
        }
        cutItem.isEnabled = !selection.isEmpty
        menu.addItem(cutItem)
        
        let pasteItem = ClosureMenuItem(title: "Paste", keyEquivalent: "v") {
            self.performPaste()
        }
        pasteItem.isEnabled = ClipboardService.shared.hasContent
        menu.addItem(pasteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let renameItem = ClosureMenuItem(title: "Rename", keyEquivalent: "") {
            self.triggerRename(selection: selection)
        }
        renameItem.isEnabled = selection.count == 1
        menu.addItem(renameItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let deleteItem = ClosureMenuItem(title: "Delete", keyEquivalent: "\u{08}") {
            self.triggerDelete(selection: selection)
        }
        deleteItem.isEnabled = !selection.isEmpty
        menu.addItem(deleteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let newFolderItem = ClosureMenuItem(title: "New Folder", keyEquivalent: "") {
            if let device = self.deviceManager.selectedDevice {
                Task { await FileOperationService.shared.newAndroidFolder(device: device, parentPath: self.viewModel.currentPath, name: "New Folder") }
            }
        }
        menu.addItem(newFolderItem)
        
        let refreshItem = ClosureMenuItem(title: "Refresh", keyEquivalent: "r") {
            self.viewModel.loadDirectory(self.viewModel.currentPath)
        }
        menu.addItem(refreshItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let copyPathItem = ClosureMenuItem(title: "Copy Path", keyEquivalent: "") {
            if let first = selection.first {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(first, forType: .string)
            }
        }
        copyPathItem.isEnabled = !selection.isEmpty
        menu.addItem(copyPathItem)
        
        return menu
    }
}

class ClosureMenuItem: NSMenuItem {
    private var actionClosure: () -> Void
    
    init(title: String, keyEquivalent: String, action: @escaping () -> Void) {
        self.actionClosure = action
        super.init(title: title, action: #selector(invokeAction), keyEquivalent: keyEquivalent)
        self.target = self
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func invokeAction() {
        actionClosure()
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct StandaloneFileManagerView: View {
    @ObservedObject var deviceManager: DeviceManager
    @StateObject private var viewModel: DirectoryViewModel
    @ObservedObject var transferService = TransferService.shared
    
    init(deviceManager: DeviceManager) {
        self.deviceManager = deviceManager
        let device = deviceManager.selectedDevice ?? AndroidDevice(serial: "dummy", model: "Dummy", status: "offline")
        _viewModel = StateObject(wrappedValue: DirectoryViewModel(device: device))
    }
    
    var body: some View {
        if deviceManager.selectedDevice != nil {
            ZStack {
                FileManagerView(deviceManager: deviceManager, viewModel: viewModel)
                
                if transferService.state != .idle {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    TransferProgressView {
                        viewModel.loadDirectory(viewModel.currentPath)
                    }
                }
            }
        } else {
            Text("No device connected")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
