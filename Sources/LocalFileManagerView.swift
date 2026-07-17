import SwiftUI
import UniformTypeIdentifiers

struct LocalFileManagerView: View {
    @ObservedObject var viewModel: LocalDirectoryViewModel
    
    @State private var showDeleteConfirmation = false
    @State private var itemsToDelete: [String] = []
    
    @State private var showRenamePrompt = false
    @State private var itemToRename: URL? = nil
    @State private var newName: String = ""
    
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
                NativeFileBrowser(items: viewModel.files, selection: $viewModel.selectedFileIDs, isLoading: viewModel.isLoading) { item in
                    if item.isDirectory {
                        viewModel.loadDirectory(item.url)
                    } else {
                        NSWorkspace.shared.open(item.url)
                    }
                } contextMenuProvider: { selection in
                    return buildContextMenu(selection: selection)
                }
                // Context Menu handled by NativeFileBrowser
                .background {
                    Group {
                        Button(action: { ClipboardService.shared.copy(paths: Array(viewModel.selectedFileIDs), platform: .mac) }) { }
                            .keyboardShortcut("c", modifiers: .command)
                            
                        Button(action: { ClipboardService.shared.cut(paths: Array(viewModel.selectedFileIDs), platform: .mac) }) { }
                            .keyboardShortcut("x", modifiers: .command)
                            
                        Button(action: { performPaste() }) { }
                            .keyboardShortcut("v", modifiers: .command)
                            
                        Button(action: { viewModel.selectedFileIDs = Set(viewModel.files.map { $0.id }) }) { }
                            .keyboardShortcut("a", modifiers: .command)
                            
                        Button(action: { triggerDelete(selection: viewModel.selectedFileIDs) }) { }
                            .keyboardShortcut(.delete, modifiers: [])
                            
                        Button(action: { triggerDelete(selection: viewModel.selectedFileIDs) }) { }
                            .keyboardShortcut(.delete, modifiers: .command)
                            
                        Button(action: { viewModel.refresh() }) { }
                            .keyboardShortcut("r", modifiers: .command)
                            
                        Button(action: {
                            let urls = viewModel.selectedFileIDs.map { URL(fileURLWithPath: $0) }
                            Task { await FileOperationService.shared.duplicateMacFiles(urls: Array(urls)) }
                        }) { }
                            .keyboardShortcut("d", modifiers: .command)
                    }
                    .opacity(0)
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
        .onAppear {
            if viewModel.currentURL == nil {
                viewModel.loadDirectory(rootURL)
            }
        }
        .alert("Move \(itemsToDelete.count) selected items to Trash?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Move to Trash", role: .destructive) {
                let urls = itemsToDelete.map { URL(fileURLWithPath: $0) }
                Task { await FileOperationService.shared.deleteMacFiles(urls: urls) }
            }
        } message: {
            Text("These items will be moved to the Trash.")
        }
        .alert("Rename File", isPresented: $showRenamePrompt) {
            TextField("New Name", text: $newName)
            Button("Cancel", role: .cancel) { }
            Button("Rename") {
                if let url = itemToRename {
                    Task { await FileOperationService.shared.renameMacFile(url: url, newName: newName) }
                }
            }
        } message: {
            Text("Enter a new name for this item.")
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
    
    private func performPaste() {
        guard let item = ClipboardService.shared.currentItem, let dest = viewModel.currentURL else { return }
        
        if item.platform == .android {
            guard let deviceSerial = item.sourceDeviceSerial else { return }
            let device = AndroidDevice(serial: deviceSerial, model: "Unknown", status: "device")
            Task {
                await TransferService.shared.prepareTransfer(
                    device: device,
                    direction: .androidToMac,
                    sourcePaths: item.paths,
                    destination: dest,
                    isBackup: false
                )
            }
        } else {
            let urls = item.paths.map { URL(fileURLWithPath: $0) }
            if item.action == .copy {
                Task { await FileOperationService.shared.duplicateMacFiles(urls: urls) }
            } else {
                // macOS to macOS Move could be implemented here
            }
        }
        
        if item.action == .cut { ClipboardService.shared.clear() }
    }
    
    private func buildContextMenu(selection: Set<String>) -> NSMenu? {
        let menu = NSMenu()
        
        let openItem = ClosureMenuItem(title: "Open", keyEquivalent: "") {
            for id in selection {
                let url = URL(fileURLWithPath: id)
                NSWorkspace.shared.open(url)
            }
        }
        openItem.isEnabled = !selection.isEmpty
        menu.addItem(openItem)
        
        let revealItem = ClosureMenuItem(title: "Reveal in Finder", keyEquivalent: "") {
            for id in selection {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: id)])
            }
        }
        revealItem.isEnabled = !selection.isEmpty
        menu.addItem(revealItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let copyItem = ClosureMenuItem(title: "Copy", keyEquivalent: "c") {
            ClipboardService.shared.copy(paths: Array(selection), platform: .mac)
        }
        copyItem.isEnabled = !selection.isEmpty
        menu.addItem(copyItem)
        
        let cutItem = ClosureMenuItem(title: "Cut", keyEquivalent: "x") {
            ClipboardService.shared.cut(paths: Array(selection), platform: .mac)
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
        
        let duplicateItem = ClosureMenuItem(title: "Duplicate", keyEquivalent: "d") {
            let urls = selection.map { URL(fileURLWithPath: $0) }
            Task { await FileOperationService.shared.duplicateMacFiles(urls: Array(urls)) }
        }
        duplicateItem.isEnabled = !selection.isEmpty
        menu.addItem(duplicateItem)
        
        let deleteItem = ClosureMenuItem(title: "Move to Trash", keyEquivalent: "\u{08}") {
            self.triggerDelete(selection: selection)
        }
        deleteItem.isEnabled = !selection.isEmpty
        menu.addItem(deleteItem)
        
        menu.addItem(NSMenuItem.separator())
        
        let newFolderItem = ClosureMenuItem(title: "New Folder", keyEquivalent: "") {
            if let cur = self.viewModel.currentURL {
                Task { await FileOperationService.shared.newMacFolder(parentURL: cur, name: "New Folder") }
            }
        }
        menu.addItem(newFolderItem)
        
        let refreshItem = ClosureMenuItem(title: "Refresh", keyEquivalent: "r") {
            self.viewModel.refresh()
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
