import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct FileManagerView: View {
    @ObservedObject var deviceManager: DeviceManager
    @ObservedObject var viewModel: DirectoryViewModel
    var onFocus: () -> Void
    
    @State private var showDeleteConfirmation = false
    @State private var itemsToDelete: [String] = []
    
    @State private var showRenamePrompt = false
    @State private var itemToRename: String? = nil
    @State private var newName: String = ""
    
    @State private var showNewFolderSheet = false
    @State private var operationError: String? = nil
    
    private var coordinator: AndroidDirectoryMutationCoordinator {
        AndroidDirectoryMutationCoordinator(viewModel: viewModel)
    }
    
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
                                Button("Internal Storage") { viewModel.loadDirectory("/sdcard") }
                                Button("Camera") { viewModel.loadDirectory("/sdcard/DCIM/Camera") }
                                Button("Downloads") { viewModel.loadDirectory("/sdcard/Download") }
                                Button("Movies") { viewModel.loadDirectory("/sdcard/Movies") }
                                Button("Music") { viewModel.loadDirectory("/sdcard/Music") }
                                Button("WhatsApp") { viewModel.loadDirectory("/sdcard/Android/media/com.whatsapp/WhatsApp/Media") }
                            }
                        }
                        .listStyle(.sidebar)
                        .frame(minWidth: 150, idealWidth: 200, maxWidth: 300, maxHeight: .infinity)
                        
                        NativeFileBrowser(
                            items: viewModel.files,
                            selection: $viewModel.selectedFileIDs,
                            isLoading: viewModel.isLoading,
                            onDoubleClick: { item in
                                if item.isDirectory {
                                    viewModel.loadDirectory(item.path)
                                }
                            },
                            contextMenuProvider: { selection in
                                return buildContextMenu(selection: selection)
                            },
                            onFocus: onFocus
                        )
                        // Menu is handled by NativeFileBrowser now
                        .frame(minWidth: 400, maxHeight: .infinity)
                    }
                    
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
            // .onAppear removed, viewModel init triggers load
            .alert("Delete \(itemsToDelete.count) selected items?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let device = deviceManager.selectedDevice {
                        let paths = itemsToDelete
                        Task {
                            do { try await coordinator.delete(paths: paths, device: device) }
                            catch { operationError = error.localizedDescription }
                        }
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
            .sheet(isPresented: $showNewFolderSheet) {
                NewFolderSheet(
                    parentURL: nil,
                    parentPath: viewModel.currentPath,
                    platform: .android,
                    onCancel: {
                        showNewFolderSheet = false
                        print("[DebugLogger] Android Folder Creation Cancelled in \(viewModel.currentPath)")
                    },
                    onCreate: { name in
                        Task {
                            do {
                                if let device = deviceManager.selectedDevice {
                                    try await coordinator.createFolder(name: name, device: device)
                                    showNewFolderSheet = false
                                }
                            } catch {
                                operationError = error.localizedDescription
                            }
                        }
                    }
                )
            }
            .alert(
                "Operation Failed",
                isPresented: Binding<Bool>(
                    get: { operationError != nil },
                    set: { if !$0 { operationError = nil } }
                ),
                presenting: operationError
            ) { _ in
                Button("OK", role: .cancel) { }
            } message: { errorMsg in
                Text(errorMsg)
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
        TransferEngine.shared.executePaste(destPlatform: .android, destPath: viewModel.currentPath, destURL: URL(fileURLWithPath: viewModel.currentPath))
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
        let vm = viewModel
        let dm = deviceManager
        
        let openItem = ClosureMenuItem(title: "Open", keyEquivalent: "") {
            if let selectedID = selection.first,
               let file = vm.files.first(where: { $0.id == selectedID }),
               file.isDirectory {
                vm.loadDirectory(file.path)
            }
        }
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let copyItem = ClosureMenuItem(title: "Copy", keyEquivalent: "") {
            ClipboardManager.shared.copy(paths: Array(selection), platform: .android, deviceSerial: dm.selectedDevice?.serial)
        }
        copyItem.isEnabled = !selection.isEmpty
        menu.addItem(copyItem)
        
        let cutItem = ClosureMenuItem(title: "Cut", keyEquivalent: "") {
            ClipboardManager.shared.cut(paths: Array(selection), platform: .android, deviceSerial: dm.selectedDevice?.serial)
        }
        cutItem.isEnabled = !selection.isEmpty
        menu.addItem(cutItem)
        
        let pasteItem = ClosureMenuItem(title: "Paste", keyEquivalent: "") {
            performPaste()
        }
        pasteItem.isEnabled = ClipboardManager.shared.hasContent
        menu.addItem(pasteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let renameItem = ClosureMenuItem(title: "Rename", keyEquivalent: "") {
            triggerRename(selection: selection)
        }
        renameItem.isEnabled = selection.count == 1
        menu.addItem(renameItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let deleteItem = ClosureMenuItem(title: "Delete", keyEquivalent: "\u{08}") {
            triggerDelete(selection: selection)
        }
        deleteItem.isEnabled = !selection.isEmpty
        menu.addItem(deleteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let newFolderItem = ClosureMenuItem(title: "New Folder", keyEquivalent: "") {
            showNewFolderSheet = true
        }
        menu.addItem(newFolderItem)
        
        let refreshItem = ClosureMenuItem(title: "Refresh", keyEquivalent: "r") {
            vm.loadDirectory(vm.currentPath)
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

@MainActor
class ClosureMenuItem: NSMenuItem {
    private var actionClosure: @MainActor () -> Void
    
    init(title: String, keyEquivalent: String, action: @escaping @MainActor () -> Void) {
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
    @ObservedObject var deviceManager = DeviceManager.shared
    @StateObject private var viewModel: DirectoryViewModel
    @ObservedObject var transferService = TransferService.shared
    
    init() {
        let device = DeviceManager.shared.selectedDevice! // Guaranteed to exist because we are in .ready state
        _viewModel = StateObject(wrappedValue: DirectoryViewModel(device: device))
    }
    
    var body: some View {
        if deviceManager.selectedDevice != nil {
            ZStack {
                FileManagerView(deviceManager: deviceManager, viewModel: viewModel, onFocus: {})
                
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
