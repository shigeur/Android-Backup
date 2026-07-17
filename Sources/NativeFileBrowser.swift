import SwiftUI
import AppKit

struct NativeFileBrowser<Item: FileBrowserItem>: NSViewControllerRepresentable {
    var items: [Item]
    @Binding var selection: Set<String>
    var isLoading: Bool = false
    
    var onDoubleClick: (Item) -> Void
    var contextMenuProvider: (Set<String>) -> NSMenu?
    
    func makeNSViewController(context: Context) -> FileBrowserViewController<Item> {
        let vc = FileBrowserViewController<Item>()
        vc.onSelectionChange = { newSelection in
            DispatchQueue.main.async {
                self.selection = newSelection
            }
        }
        vc.onDoubleClick = onDoubleClick
        vc.contextMenuProvider = contextMenuProvider
        return vc
    }
    
    func updateNSViewController(_ nsViewController: FileBrowserViewController<Item>, context: Context) {
        nsViewController.update(items: items, selection: selection, isLoading: isLoading)
        nsViewController.onDoubleClick = onDoubleClick
        nsViewController.contextMenuProvider = contextMenuProvider
    }
}

class FileBrowserViewController<Item: FileBrowserItem>: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    
    private var scrollView: NSScrollView!
    private var tableView: NSTableView!
    
    private var items: [Item] = []
    
    var onSelectionChange: ((Set<String>) -> Void)?
    var onDoubleClick: ((Item) -> Void)?
    var contextMenuProvider: ((Set<String>) -> NSMenu?)?
    
    // Prevent recursive updates
    private var isUpdatingSelection = false
    private var isUpdating = false
    private var isTableReady = false
    
    // Overlays
    private var overlayContainer: NSView!
    private var loadingSpinner: NSProgressIndicator!
    private var loadingLabel: NSTextField!
    private var emptyStateLabel: NSTextField!
    
    override func loadView() {
        self.view = NSView()
        
        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        
        tableView = NSTableView()
        tableView.dataSource = self
        tableView.delegate = self
        tableView.allowsMultipleSelection = true
        tableView.rowSizeStyle = .medium
        tableView.style = .inset
        
        // Double click action
        tableView.doubleAction = #selector(handleDoubleClick)
        tableView.target = self
        
        // State restoration
        tableView.autosaveName = "NativeFileBrowserTable"
        tableView.autosaveTableColumns = true
        
        // Columns
        let nameCol = NSTableColumn(identifier: .init("Name"))
        nameCol.title = "Name"
        nameCol.minWidth = 200
        nameCol.sortDescriptorPrototype = NSSortDescriptor(key: "Name", ascending: true)
        
        let sizeCol = NSTableColumn(identifier: .init("Size"))
        sizeCol.title = "Size"
        sizeCol.width = 100
        sizeCol.sortDescriptorPrototype = NSSortDescriptor(key: "Size", ascending: true)
        
        let modCol = NSTableColumn(identifier: .init("Modified"))
        modCol.title = "Modified"
        modCol.width = 150
        modCol.sortDescriptorPrototype = NSSortDescriptor(key: "Modified", ascending: false)
        
        tableView.addTableColumn(nameCol)
        tableView.addTableColumn(sizeCol)
        tableView.addTableColumn(modCol)
        
        scrollView.documentView = tableView
        view.addSubview(scrollView)
        
        // Overlays
        overlayContainer = NSView()
        overlayContainer.translatesAutoresizingMaskIntoConstraints = false
        overlayContainer.wantsLayer = true
        overlayContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.8).cgColor
        overlayContainer.alphaValue = 0.0
        overlayContainer.isHidden = true
        view.addSubview(overlayContainer)
        
        loadingSpinner = NSProgressIndicator()
        loadingSpinner.translatesAutoresizingMaskIntoConstraints = false
        loadingSpinner.style = .spinning
        overlayContainer.addSubview(loadingSpinner)
        
        loadingLabel = NSTextField(labelWithString: "Reading folder contents...")
        loadingLabel.translatesAutoresizingMaskIntoConstraints = false
        loadingLabel.textColor = .secondaryLabelColor
        loadingLabel.font = .systemFont(ofSize: 13)
        overlayContainer.addSubview(loadingLabel)
        
        emptyStateLabel = NSTextField(labelWithString: "This folder is empty.")
        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.textColor = .tertiaryLabelColor
        emptyStateLabel.font = .systemFont(ofSize: 18, weight: .medium)
        emptyStateLabel.alphaValue = 0.0
        emptyStateLabel.isHidden = true
        view.addSubview(emptyStateLabel)
        
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            overlayContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayContainer.topAnchor.constraint(equalTo: view.topAnchor),
            overlayContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            loadingSpinner.centerXAnchor.constraint(equalTo: overlayContainer.centerXAnchor),
            loadingSpinner.centerYAnchor.constraint(equalTo: overlayContainer.centerYAnchor, constant: -16),
            
            loadingLabel.centerXAnchor.constraint(equalTo: overlayContainer.centerXAnchor),
            loadingLabel.topAnchor.constraint(equalTo: loadingSpinner.bottomAnchor, constant: 8),
            
            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    override func rightMouseDown(with event: NSEvent) {
        let globalLocation = event.locationInWindow
        let localLocation = tableView.convert(globalLocation, from: nil)
        let clickedRow = tableView.row(at: localLocation)
        
        if clickedRow != -1 {
            if !tableView.selectedRowIndexes.contains(clickedRow) {
                tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            }
        } else {
            tableView.deselectAll(nil)
        }
        
        let selectionSet = currentSelectionSet()
        if let menu = contextMenuProvider?(selectionSet) {
            NSMenu.popUpContextMenu(menu, with: event, for: tableView)
        } else {
            super.rightMouseDown(with: event)
        }
    }
    
    func update(items: [Item], selection: Set<String>, isLoading: Bool = false) {
        guard !isUpdating else {
            print("[NativeFileBrowser] update() skipped to prevent recursion.")
            return
        }
        isUpdating = true
        defer { isUpdating = false }
        
        print("[NativeFileBrowser] update() called with \(items.count) items, selection count: \(selection.count), isLoading: \(isLoading)")
        
        var sortedItems = items
        if let sortDescriptor = tableView.sortDescriptors.first {
            sortedItems.sort { a, b in
                let key = sortDescriptor.key
                let asc = sortDescriptor.ascending
                
                if a.isDirectory != b.isDirectory {
                    return a.isDirectory // Folders always first
                }
                
                if key == "Name" {
                    return asc ? a.name.localizedStandardCompare(b.name) == .orderedAscending : a.name.localizedStandardCompare(b.name) == .orderedDescending
                } else if key == "Size" {
                    return asc ? a.size < b.size : a.size > b.size
                } else if key == "Modified" {
                    return asc ? a.modifiedDate < b.modifiedDate : a.modifiedDate > b.modifiedDate
                }
                return false
            }
        }
        
        let changed = self.items.map { $0.id } != sortedItems.map { $0.id }
        self.items = sortedItems
        
        if changed {
            print("[NativeFileBrowser] Data changed. Reloading table.")
            tableView.reloadData()
        }
        
        if isLoading {
            overlayContainer.isHidden = false
            if isTableReady {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    overlayContainer.animator().alphaValue = 1.0
                }
            } else {
                overlayContainer.alphaValue = 1.0
            }
            loadingSpinner.startAnimation(nil)
            emptyStateLabel.isHidden = true
        } else {
            if isTableReady {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.2
                    overlayContainer.animator().alphaValue = 0.0
                }, completionHandler: {
                    if !isLoading {
                        self.overlayContainer.isHidden = true
                    }
                })
            } else {
                overlayContainer.alphaValue = 0.0
                overlayContainer.isHidden = true
            }
            loadingSpinner.stopAnimation(nil)
            
            if self.items.isEmpty {
                emptyStateLabel.isHidden = false
                if isTableReady {
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = 0.2
                        emptyStateLabel.animator().alphaValue = 1.0
                    }
                } else {
                    emptyStateLabel.alphaValue = 1.0
                }
            } else {
                emptyStateLabel.isHidden = true
            }
        }
        
        // Update selection safely without triggering delegate loop
        guard !self.items.isEmpty else {
            if !tableView.selectedRowIndexes.isEmpty {
                tableView.deselectAll(nil)
            }
            if !isTableReady {
                isTableReady = true
                print("[NativeFileBrowser] Table initialization complete.")
            }
            return
        }
        
        isUpdatingSelection = true
        var validIndexes = IndexSet()
        for id in selection {
            if let index = self.items.firstIndex(where: { $0.id == id }) {
                if index >= 0 && index < self.items.count {
                    validIndexes.insert(index)
                }
            }
        }
        
        if tableView.selectedRowIndexes != validIndexes {
            print("[NativeFileBrowser] Restoring selection to \(validIndexes.count) valid rows.")
            tableView.selectRowIndexes(validIndexes, byExtendingSelection: false)
        }
        isUpdatingSelection = false
        
        if !isTableReady {
            isTableReady = true
            print("[NativeFileBrowser] Table initialization complete.")
        }
    }
    
    @objc private func handleDoubleClick() {
        let clickedRow = tableView.clickedRow
        guard clickedRow >= 0, clickedRow < items.count else { return }
        onDoubleClick?(items[clickedRow])
    }
    
    private func currentSelectionSet() -> Set<String> {
        let selectedIndexes = tableView.selectedRowIndexes
        var set = Set<String>()
        for idx in selectedIndexes {
            if idx < items.count {
                set.insert(items[idx].id)
            }
        }
        return set
    }
    
    // MARK: - NSTableViewDataSource
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }
    
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        guard row < items.count else { return nil }
        return items[row].pasteboardWriter
    }
    
    // MARK: - NSTableViewDelegate
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        guard isTableReady else {
            print("[NativeFileBrowser] Ignored sortDescriptorsDidChange because table is initializing.")
            return
        }
        print("[NativeFileBrowser] sortDescriptorsDidChange triggered. New keys: \(tableView.sortDescriptors.compactMap { $0.key })")
        // Re-sort current items based on new descriptors
        update(items: self.items, selection: currentSelectionSet())
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingSelection else { return }
        let set = currentSelectionSet()
        onSelectionChange?(set)
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < items.count else { return nil }
        let item = items[row]
        
        let identifier = tableColumn?.identifier.rawValue ?? ""
        let viewIdentifier = NSUserInterfaceItemIdentifier("Cell_\(identifier)")
        
        var cell = tableView.makeView(withIdentifier: viewIdentifier, owner: self) as? NSTableCellView
        if cell == nil {
            cell = NSTableCellView()
            cell?.identifier = viewIdentifier
            
            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            
            cell?.addSubview(textField)
            cell?.textField = textField
            
            if identifier == "Name" {
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                cell?.addSubview(imageView)
                cell?.imageView = imageView
                
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                    imageView.centerYAnchor.constraint(equalTo: cell!.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
                ])
            } else {
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                    textField.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
                ])
            }
        }
        
        if identifier == "Name" {
            cell?.textField?.stringValue = item.name
            cell?.imageView?.image = item.iconImage
        } else if identifier == "Size" {
            cell?.textField?.stringValue = item.isDirectory ? "--" : formatBytes(item.size)
            cell?.textField?.textColor = .secondaryLabelColor
        } else if identifier == "Modified" {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            cell?.textField?.stringValue = formatter.string(from: item.modifiedDate)
            cell?.textField?.textColor = .secondaryLabelColor
        }
        
        return cell
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
