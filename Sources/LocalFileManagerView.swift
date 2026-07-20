import SwiftUI
import UniformTypeIdentifiers
import Combine

@MainActor
struct LocalFileManagerView: View {
    @ObservedObject var viewModel: LocalDirectoryViewModel
    var onFocus: () -> Void
    
    @State private var showDeleteConfirmation = false
    @State private var itemsToDelete: [String] = []
    
    @State private var showRenamePrompt = false
    @State private var itemToRename: URL? = nil
    @State private var newName: String = ""
    
    @State private var showNewFolderSheet = false
    @State private var operationError: String? = nil
    
    private var coordinator: LocalDirectoryMutationCoordinator {
        LocalDirectoryMutationCoordinator(viewModel: viewModel)
    }
    
    // We statically define the root as HOME since Sandbox is off
    private var rootURL: URL {
        URL(fileURLWithPath: ProcessInfo.processInfo.environment["HOME"] ?? "/")
    }
    
    var breadcrumbs: [URL] {
        guard let current = viewModel.currentURL else { return [] }
        
        var paths: [URL] = []
        var u = current
        
        while u.path != rootURL.path && u.path != "/" {
            paths.append(u)
            u = u.deletingLastPathComponent()
        }
        paths.append(rootURL)
        
        return paths.reversed()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar/Breadcrumbs
            HStack {
                Button(action: { viewModel.navigateUp() }) {
                    Image(systemName: "arrow.up")
                }
                .disabled(viewModel.currentURL == rootURL)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(breadcrumbs, id: \.self) { url in
                            if url != breadcrumbs.first {
                                Text(">").foregroundColor(.secondary)
                            }
                            Button(url == rootURL ? "Home" : url.lastPathComponent) {
                                viewModel.loadDirectory(url)
                            }
                        }
                    }
                }
                
                Spacer()
                
                Button(action: { viewModel.refresh() }) {
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
                        if let cur = viewModel.currentURL {
                            viewModel.loadDirectory(cur)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                NativeFileBrowser(
                    items: viewModel.files,
                    selection: $viewModel.selectedFileIDs,
                    isLoading: viewModel.isLoading,
                    onDoubleClick: { item in
                        if item.isDirectory {
                            viewModel.loadDirectory(item.url)
                        }
                    },
                    contextMenuProvider: { selection in
                        return buildContextMenu(selection: selection)
                    },
                    onFocus: onFocus
                )
                .sheet(isPresented: $showNewFolderSheet) {
                    NewFolderSheet(
                        parentURL: viewModel.currentURL,
                        parentPath: nil,
                        platform: .mac,
                        onCancel: {
                            showNewFolderSheet = false
                            if let path = viewModel.currentURL?.path {
                                print("[DebugLogger] Folder Creation Cancelled in \(path)")
                            } else {
                                print("[DebugLogger] Folder Creation Cancelled")
                            }
                        },
                        onCreate: { name in
                            Task {
                                do {
                                    try await coordinator.createFolder(name: name)
                                    showNewFolderSheet = false
                                } catch {
                                    operationError = error.localizedDescription
                                }
                            }
                        }
                    )
                }
                
                // Loading handled in NativeFileBrowser
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
                
                Text("Mac Local")
                    .foregroundColor(.secondary)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MacTriggerDelete"))) { _ in
            triggerDelete(selection: viewModel.selectedFileIDs)
        }
        .onAppear {
            if viewModel.currentURL == nil {
                viewModel.loadDirectory(rootURL)
            }
        }
        .alert("Move \(itemsToDelete.count) selected items to Trash?", isPresented: $showDeleteConfirmation) {
            Button(role: .cancel, action: { }) {
                Label("Cancel", systemImage: "xmark.circle.fill")
            }
            Button(role: .destructive, action: {
                let urls = itemsToDelete.map { URL(fileURLWithPath: $0) }
                Task {
                    do { try await self.coordinator.delete(urls: urls) }
                    catch { operationError = error.localizedDescription }
                }
            }) {
                Label("Move to Trash", systemImage: "trash.fill")
            }
        } message: {
            Text("These items will be moved to the Trash.")
        }
        .alert("Rename File", isPresented: $showRenamePrompt) {
            TextField("New Name", text: $newName)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                if let url = itemToRename {
                    Task {
                        do { try await coordinator.rename(url: url, newName: newName) }
                        catch { operationError = error.localizedDescription }
                    }
                }
            }
        } message: {
            Text("Enter a new name for this item.")
        }
        .alert(
            "Operation Failed",
            isPresented: Binding<Bool>(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            ),
            presenting: operationError
        ) { _ in
            Button(role: .cancel, action: { }) {
                Label("OK", systemImage: "checkmark.circle.fill")
            }
        } message: { errorMsg in
            Text(errorMsg)
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func triggerDelete(selection: Set<String>) {
        guard !selection.isEmpty else { return }
        itemsToDelete = Array(selection)
        showDeleteConfirmation = true
    }
    

    private func triggerRename(selection: Set<String>) {
        if let selectedID = selection.first, let file = viewModel.files.first(where: { $0.id == selectedID }) {
            itemToRename = file.url
            newName = file.name
            showRenamePrompt = true
        }
    }
    
    @MainActor
    private func performPaste() {
        guard let item = ClipboardManager.shared.currentItem, let dest = viewModel.currentURL else { return }
        
        let urls = item.paths.map { URL(fileURLWithPath: $0) }
        
        let task = Task {
            if item.platform == .mac {
                if item.action == .cut {
                    await FileOperationService.shared.moveMacFiles(urls: urls, to: dest)
                } else {
                    await FileOperationService.shared.copyMacFiles(urls: urls, to: dest)
                }
            } else {
                guard let deviceSerial = item.sourceDeviceSerial, let device = DeviceLifecycleManager.shared.currentDevice, device.serial == deviceSerial else { return }
                let session = TransferProgressPublisher.shared.createSession(device: device, direction: .androidToMac, destination: dest, isBackup: false)
                await TransferService.shared.prepareTransfer(session: session, sourcePaths: item.paths, duplicateMode: .fast)
            }
        }
        TransferProgressPublisher.shared.activeSessions.values.first?.setActiveTask(task)
        
        if item.action == .cut { ClipboardManager.shared.clear() }
    }
    
    @MainActor
    private func buildContextMenu(selection: Set<String>) -> NSMenu? {
        let menu = NSMenu()
        let vm = viewModel
        
        let openItem = ClosureMenuItem(title: "Open", keyEquivalent: "") {
            if let selectedID = selection.first,
               let file = vm.files.first(where: { $0.id == selectedID }),
               file.isDirectory {
                vm.loadDirectory(URL(fileURLWithPath: file.path))
            } else {
                for id in selection {
                    let url = URL(fileURLWithPath: id)
                    NSWorkspace.shared.open(url)
                }
            }
        }
        menu.addItem(openItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let copyItem = ClosureMenuItem(title: "Copy", keyEquivalent: "") {
            ClipboardManager.shared.copy(paths: Array(selection), platform: .mac)
        }
        copyItem.isEnabled = !selection.isEmpty
        menu.addItem(copyItem)
        
        let cutItem = ClosureMenuItem(title: "Cut", keyEquivalent: "") {
            ClipboardManager.shared.cut(paths: Array(selection), platform: .mac)
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
        
        let duplicateItem = ClosureMenuItem(title: "Duplicate", keyEquivalent: "d") {
            let urls = selection.map { URL(fileURLWithPath: $0) }
            Task {
                do { try await self.coordinator.duplicate(urls: Array(urls)) }
                catch { self.operationError = error.localizedDescription }
            }
        }
        duplicateItem.isEnabled = !selection.isEmpty
        menu.addItem(duplicateItem)
        
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
            vm.refresh()
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
