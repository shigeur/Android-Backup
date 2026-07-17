import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()
    
    // Deletion states
    @State private var showDeleteConfirmation = false
    @State private var showFilesDeleteConfirmation = false
    @State private var itemsToDelete: Set<String>? = nil // nil means all
    
    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                if viewModel.allSessions.isEmpty {
                    emptyState
                } else {
                    List(selection: $viewModel.selectedSessions) {
                        ForEach(viewModel.filteredSessions, id: \.id) { session in
                            HistoryRowView(session: session)
                                .tag(session.id)
                                .contextMenu {
                                    Button("Delete Backup History") {
                                        itemsToDelete = [session.id]
                                        showDeleteConfirmation = true
                                    }
                                    Button("Delete Backup Files") {
                                        itemsToDelete = [session.id]
                                        showFilesDeleteConfirmation = true
                                    }
                                    
                                    Divider()
                                    
                                    Button("Show Details") {
                                        // Placeholder for future feature
                                    }
                                }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            
            // Undo Overlay
            if let undoAction = viewModel.undoItemQueue.last {
                VStack {
                    Spacer()
                    HStack {
                        Text("Deleted \(undoAction.sessions.count) backup records")
                            .foregroundColor(.white)
                        Spacer()
                        Button("Undo") {
                            withAnimation {
                                viewModel.abortUndo(id: undoAction.id)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundColor(.black)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.9))
                    .cornerRadius(8)
                    .padding()
                    .shadow(radius: 5)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItemGroup {
                Button(action: {
                    viewModel.loadSessions()
                }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                
                Button(action: {
                    itemsToDelete = viewModel.selectedSessions.isEmpty ? nil : viewModel.selectedSessions
                    showDeleteConfirmation = true
                }) {
                    Label("Clear History", systemImage: "trash")
                }
                .disabled(viewModel.allSessions.isEmpty)
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search history...")
        // Confirmation Dialogs
        .confirmationDialog(
            "Clear Backup History?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete History Only", role: .destructive) {
                viewModel.deleteHistory(sessions: itemsToDelete, deleteFilesOnDisk: false)
            }
            Button("Delete History + Backup Files", role: .destructive) {
                // Show second confirmation
                showFilesDeleteConfirmation = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let items = itemsToDelete, !items.isEmpty {
                Text("This action will permanently remove \(items.count) backup history records.\nYour actual backup files on disk will NOT be deleted unless you choose that option.")
            } else {
                Text("This action will permanently remove ALL backup history records.\nYour actual backup files on disk will NOT be deleted unless you choose that option.")
            }
        }
        .confirmationDialog(
            "Permanently Delete Backup Files?",
            isPresented: $showFilesDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete History & Files", role: .destructive) {
                viewModel.deleteHistory(sessions: itemsToDelete, deleteFilesOnDisk: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the selected backup history and all corresponding backup folders stored on your Mac.\nThis action cannot be undone.")
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Backup History Yet")
                .font(.title)
                .fontWeight(.semibold)
            
            Text("Your completed Android backups will appear here.")
                .foregroundColor(.secondary)
            
            Button("Start Your First Backup") {
                // Future integration to switch tab/view
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct HistoryRowView: View {
    let session: BackupSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.startedAt, style: .date)
                    .font(.headline)
                Spacer()
                Text(session.status.capitalized)
                    .foregroundColor(session.status.lowercased() == "success" ? .green : .orange)
                    .fontWeight(.bold)
            }
            
            HStack(spacing: 20) {
                Label(formatBytes(session.transferredBytes), systemImage: "externaldrive")
                Label("\(session.transferredFiles) files", systemImage: "doc.on.doc")
                if let finished = session.finishedAt {
                    let duration = Int(finished.timeIntervalSince(session.startedAt))
                    Label(formatDuration(duration), systemImage: "clock")
                } else {
                    Label("In Progress", systemImage: "clock.arrow.2.circlepath")
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(seconds)) ?? ""
    }
}
