import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var allSessions: [BackupSession] = []
    @Published var filteredSessions: [BackupSession] = []
    
    @Published var searchText: String = "" {
        didSet { filterSessions() }
    }
    
    @Published var selectedSessions = Set<String>()
    
    // Undo support
    @Published var undoItemQueue: [UndoAction] = []
    
    struct UndoAction: Identifiable {
        let id = UUID()
        let sessions: [BackupSession]
        let files: [BackupFile]
        var isTimerActive: Bool = true
    }
    
    init() {
        loadSessions()
    }
    
    func loadSessions() {
        do {
            let sessions = try BackupRepository.shared.getAllSessions()
            self.allSessions = sessions.sorted { $0.startedAt > $1.startedAt }
            filterSessions()
        } catch {
            print("Failed to load sessions: \(error)")
        }
    }
    
    func filterSessions() {
        if searchText.isEmpty {
            filteredSessions = allSessions
        } else {
            let lowercased = searchText.lowercased()
            filteredSessions = allSessions.filter {
                $0.status.lowercased().contains(lowercased) ||
                $0.deviceSerial.lowercased().contains(lowercased) ||
                formatDate($0.startedAt).lowercased().contains(lowercased)
            }
        }
    }
    
    // MARK: - Deletion Logic
    
    /// Delete selected items or all if nil
    func deleteHistory(sessions: Set<String>? = nil, deleteFilesOnDisk: Bool) {
        let targets = sessions ?? Set(allSessions.map { $0.id })
        let sessionsToDelete = allSessions.filter { targets.contains($0.id) }
        
        var deletedFilesTotal = 0
        var deletedBytesTotal: Int64 = 0
        var deletedFolders = 0
        
        do {
            // Pre-fetch files if we need to restore them for undo or delete from disk
            var associatedFiles: [BackupFile] = []
            var foldersToDelete: Set<String> = []
            
            for session in sessionsToDelete {
                let files = try BackupRepository.shared.getFilesForSession(sessionId: session.id)
                associatedFiles.append(contentsOf: files)
                deletedFilesTotal += files.count
                deletedBytesTotal += files.reduce(0) { $0 + $1.size }
                
                // Collect unique destination folders
                let folderURLs = files.map { URL(fileURLWithPath: $0.destinationFolder).deletingLastPathComponent().path }
                for folder in folderURLs {
                    foldersToDelete.insert(folder)
                }
            }
            
            if deleteFilesOnDisk {
                // Instantly delete without undo
                for folder in foldersToDelete {
                    do {
                        try FileManager.default.removeItem(atPath: folder)
                        deletedFolders += 1
                    } catch {
                        print("Failed to delete folder on disk: \(folder), error: \(error)")
                    }
                }
                
                // Commit to DB
                try BackupRepository.shared.deleteSessions(ids: targets)
                logDeletion(sessions: sessionsToDelete.count, files: deletedFilesTotal, bytes: deletedBytesTotal, folders: deletedFolders)
                loadSessions()
                selectedSessions.removeAll()
            } else {
                // Undo logic (history only)
                let undoAction = UndoAction(sessions: sessionsToDelete, files: associatedFiles)
                undoItemQueue.append(undoAction)
                
                // Optimistic UI update
                allSessions.removeAll { targets.contains($0.id) }
                filterSessions()
                selectedSessions.removeAll()
                
                // Start a timer to actually commit to DB after 10 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 10_000_000_000)
                    if let index = undoItemQueue.firstIndex(where: { $0.id == undoAction.id }), undoItemQueue[index].isTimerActive {
                        // Timer finished without being aborted, commit to DB
                        try? BackupRepository.shared.deleteSessions(ids: targets)
                        logDeletion(sessions: sessionsToDelete.count, files: deletedFilesTotal, bytes: deletedBytesTotal, folders: deletedFolders)
                        undoItemQueue.removeAll(where: { $0.id == undoAction.id })
                    }
                }
            }
            
        } catch {
            print("Deletion error: \(error)")
        }
    }
    
    func abortUndo(id: UUID) {
        if let index = undoItemQueue.firstIndex(where: { $0.id == id }) {
            let action = undoItemQueue[index]
            undoItemQueue[index].isTimerActive = false
            undoItemQueue.remove(at: index)
            
            // Restore to UI
            allSessions.append(contentsOf: action.sessions)
            allSessions.sort { $0.startedAt > $1.startedAt }
            filterSessions()
        }
    }
    
    // MARK: - Logging
    private func logDeletion(sessions: Int, files: Int, bytes: Int64, folders: Int) {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        let sizeStr = formatter.string(fromByteCount: bytes)
        
        let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        
        let logMessage = "[\(dateStr)] DELETED HISTORY: \(sessions) sessions, \(files) files, \(sizeStr), \(folders) folders removed from disk.\n"
        
        let logDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("AndroidBackup").appendingPathComponent("Logs")
        
        do {
            try FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
            let logFile = logDir.appendingPathComponent("history_deletion.log")
            
            if let data = logMessage.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logFile.path) {
                    let handle = try FileHandle(forWritingTo: logFile)
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                } else {
                    try data.write(to: logFile)
                }
            }
        } catch {
            print("Failed to write log: \(error)")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
