import Foundation
import Combine

@MainActor

struct TransferJob {
    let remotePath: String
    let localPath: String
    let relativePath: String
    let size: Int64
    let modifiedDate: Date
}

struct RemoteFile {
    let path: String
    let relativePath: String
    let size: Int64
    let modifiedDate: Date
}

enum DuplicateResolution {
    case skip
    case replace
}

@MainActor
class TransferService {
    static let shared = TransferService()
    
    private init() {}
    
    func prepareTransfer(
        session: TransferSession,
        sourcePaths: [String],
        duplicateMode: DuplicateDetectionMode = .fast,
        onProgress: TransferEngine.TransferProgressCallback? = nil
    ) async {
        
        onProgress?(TransferProgress(sessionID: session.id, stage: .generatingPlan))
        session.state = .scanning
        session.startScanningTimer()
        
        session.transferPlan = TransferPlan(device: session.device!, direction: session.direction, destination: session.destination, isBackup: session.isBackup)
        
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for path in sourcePaths {
                    group.addTask {
                        if session.direction == TransferDirection.androidToMac {
                            // Check Cache first
                            if let cached = await ScanCacheManager.shared.getCachedFiles(deviceSerial: (session.device?.serial ?? ""), path: path) {
                                await self.processDiscoveredFiles(cached, session: session, duplicateMode: duplicateMode)
                            } else {
                                let files = try await self.streamAndroidFileList(session: session, remotePath: path, duplicateMode: duplicateMode)
                                await ScanCacheManager.shared.setCachedFiles(deviceSerial: (session.device?.serial ?? ""), path: path, files: files)
                            }
                        } else {
                            // Mac to Android
                            let localURL = URL(fileURLWithPath: path)
                            let files = try await self.fetchMacFileList(localURL: localURL)
                            // Map local to remote
                            let remoteFiles = files.map { RemoteFile(path: (session.destination.path as NSString).appendingPathComponent($0.relativePath), relativePath: $0.relativePath, size: $0.size, modifiedDate: $0.modifiedDate) }
                            await self.processDiscoveredFiles(remoteFiles, session: session, duplicateMode: duplicateMode, originalMacFiles: files)
                        }
                    }
                }
                try await group.waitForAll()
            }
            
            session.stopScanningTimer()
            
            // Auto transition to preflight if the user hasn't cancelled
            if !session.checkCancelled() {
                session.state = .preflight
                onProgress?(TransferProgress(sessionID: session.id, stage: .waitingForConfirmation, totalFiles: session.totalFiles, totalBytes: session.totalBytesFound))
            } else {
                onProgress?(TransferProgress(sessionID: session.id, stage: .cancelled))
            }
        } catch {
            session.stopScanningTimer()
            session.state = .error(error.localizedDescription)
            let errStr = error.localizedDescription
            Task { @MainActor in
                TransferTrace.logFailure(reason: "Prepare Transfer Error", function: "prepareTransfer", error: errStr)
            }
            onProgress?(TransferProgress(sessionID: session.id, stage: .failed, errorMessage: errStr))
        }
    }
    
    private func processDiscoveredFiles(_ files: [RemoteFile], session: TransferSession, duplicateMode: DuplicateDetectionMode, originalMacFiles: [LocalFetchFile]? = nil) async {
        for (index, file) in files.enumerated() {
            if session.checkCancelled() { break }
            
            let relativePath = file.relativePath
            var localPath = ""
            var remotePath = ""
            
            if session.direction == TransferDirection.androidToMac {
                localPath = session.destination.appendingPathComponent(relativePath).path
                remotePath = file.path
            } else {
                localPath = originalMacFiles?[index].localPath ?? ""
                remotePath = file.path
            }
            
            let job = TransferJob(remotePath: remotePath, localPath: localPath, relativePath: relativePath, size: file.size, modifiedDate: file.modifiedDate)
            await self.checkDuplicateAndAppend(job: job, session: session, duplicateMode: duplicateMode)
        }
    }
    
    private func checkDuplicateAndAppend(job: TransferJob, session: TransferSession, duplicateMode: DuplicateDetectionMode) async {
        var isDuplicate = false
        var isModified = false
        
        if session.direction == TransferDirection.androidToMac {
            let fm = FileManager.default
            if fm.fileExists(atPath: job.localPath) {
                let attrs = try? fm.attributesOfItem(atPath: job.localPath)
                let localSize = attrs?[.size] as? Int64 ?? 0
                
                if duplicateMode == .fast || duplicateMode == .balanced {
                    if localSize == job.size {
                        isDuplicate = true
                    } else {
                        isModified = true
                    }
                }
            }
        } else {
            // Mac to Android
            let destDir = (job.remotePath as NSString).deletingLastPathComponent
            let fileName = (job.remotePath as NSString).lastPathComponent
            
            if let cachedFiles = await DirectoryCache.shared.getAndroidCache(for: destDir),
               let existing = cachedFiles.first(where: { $0.name == fileName }) {
                if existing.size == job.size {
                    isDuplicate = true
                } else {
                    isModified = true
                }
            } else if let record = try? BackupRepository.shared.getFile(deviceSerial: (session.device?.serial ?? ""), relativePath: job.relativePath) {
                if record.size == job.size {
                    isDuplicate = true
                } else {
                    isModified = true
                }
            }
        }
        
        // Append incrementally on Main Actor
        session.totalFiles += 1
        session.totalBytesFound += job.size
        
        if isDuplicate {
            session.transferPlan?.duplicateJobs.append(job)
            session.transferPlan?.duplicateBytes += job.size
        } else if isModified {
            session.transferPlan?.modifiedJobs.append(job)
            session.transferPlan?.totalBytes += job.size
        } else {
            session.transferPlan?.newJobs.append(job)
            session.transferPlan?.totalBytes += job.size
        }
    }
    
    private func streamAndroidFileList(session: TransferSession, remotePath: String, duplicateMode: DuplicateDetectionMode) async throws -> [RemoteFile] {
        let isDirCommand = ["-s", (session.device?.serial ?? ""), "shell", "if [ -d '\(remotePath)' ]; then echo 'DIR'; else echo 'FILE'; fi"]
        let isDirResult = try await ADBManager.shared.run(isDirCommand)
        let isDirectory = isDirResult.trimmingCharacters(in: .whitespacesAndNewlines) == "DIR"
        
        let command = ["-s", (session.device?.serial ?? ""), "shell", "find", "'\(remotePath)'", "-type", "f", "-exec", "stat", "-c", "'%s||%Y||%n'", "{}", "\\;"]
        
        let stream = ADBManager.shared.runStreaming(command)
        
        var allFiles: [RemoteFile] = []
        let remotePathName = (remotePath as NSString).lastPathComponent
        let parentDir = isDirectory ? (remotePath as NSString).deletingLastPathComponent : ""
        
        for await line in stream {
            if session.checkCancelled() { break }
            if line.isEmpty || line.contains("find: ") || line.contains("stat: ") { continue }
            
            let parts = line.components(separatedBy: "||")
            guard parts.count >= 3 else { continue }
            
            if let size = Int64(parts[0].trimmingCharacters(in: .whitespaces)), let mtime = TimeInterval(parts[1].trimmingCharacters(in: .whitespaces)) {
                let fullPath = parts[2...].joined(separator: "||").trimmingCharacters(in: .whitespaces)
                
                var relativePath = ""
                if isDirectory {
                    if parentDir != "/" {
                        relativePath = fullPath.replacingOccurrences(of: parentDir + "/", with: "")
                    } else {
                        relativePath = fullPath.replacingOccurrences(of: "/", with: "")
                    }
                } else {
                    relativePath = remotePathName
                }
                
                let file = RemoteFile(path: fullPath, relativePath: relativePath, size: size, modifiedDate: Date(timeIntervalSince1970: mtime))
                allFiles.append(file)
                
                // Process immediately
                let destFileURL = session.destination.appendingPathComponent(relativePath)
                let job = TransferJob(remotePath: file.path, localPath: destFileURL.path, relativePath: relativePath, size: file.size, modifiedDate: file.modifiedDate)
                await checkDuplicateAndAppend(job: job, session: session, duplicateMode: duplicateMode)
                
                // Trigger fast start state if we have parsed enough
                if session.totalFiles == 500 && session.state == .scanning {
                    session.state = .preflight // UI shows preflight while scan finishes in background
                }
            }
        }
        
        return allFiles
    }
    
    func executeTransfer(session: TransferSession, resolution: DuplicateResolution, onProgress: TransferEngine.TransferProgressCallback? = nil) async {
        guard let plan = session.transferPlan else { return }
        
        onProgress?(TransferProgress(sessionID: session.id, stage: .preparing))
        
        var filesToTransfer: [TransferJob] = plan.newJobs + plan.modifiedJobs
        
        await MainActor.run {
            session.state = .copying
            
            if resolution == .replace {
                filesToTransfer.append(contentsOf: plan.duplicateJobs)
                session.totalBytesToCopy = plan.totalBytes + plan.duplicateBytes
                session.skippedFiles = 0
            } else {
                // skip duplicates
                session.totalBytesToCopy = plan.totalBytes
                session.skippedFiles = plan.duplicateJobs.count
            }
            
            session.totalFiles = plan.newJobs.count + plan.modifiedJobs.count + plan.duplicateJobs.count
            session.copiedFiles = 0
            session.bytesCopied = 0
        }
        
        onProgress?(TransferProgress(sessionID: session.id, stage: .started, percentage: 0, filesCompleted: 0, totalFiles: session.totalFiles, bytesCopied: 0, totalBytes: session.totalBytesToCopy))
        
        session.startCopyingTimer()
        
        createdAndroidDirectories.removeAll()
        
        for job in filesToTransfer {
            if session.checkCancelled() { break }
            
            await MainActor.run {
                session.currentFile = job.relativePath
                session.currentLocalPath = job.localPath
                session.currentRemotePath = job.remotePath
                session.progress = Double(session.copiedFiles + session.skippedFiles) / Double(max(1, session.totalFiles))
            }
            
            onProgress?(TransferProgress(sessionID: session.id, stage: .copying, percentage: session.progress, filesCompleted: session.copiedFiles + session.skippedFiles, totalFiles: session.totalFiles, bytesCopied: session.bytesCopied, totalBytes: session.totalBytesToCopy, currentFileName: URL(fileURLWithPath: session.currentFile).lastPathComponent, estimatedRemainingTime: session.estimatedRemainingTime))
            
            // Start the file estimator for smooth UI progress
            session.startFileEstimator(fileSize: job.size)
            
            // For Android to Mac, we can also poll the local file size to be highly accurate
            let filePollTask = Task {
                while !Task.isCancelled {
                    if session.direction == TransferDirection.androidToMac {
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: job.localPath),
                           let currentSize = attrs[.size] as? Int64 {
                            await MainActor.run {
                                session.currentFileBytesCopied = min(currentSize, job.size)
                            }
                        }
                    }
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                }
            }
            
            do {
                if session.direction == TransferDirection.androidToMac {
                    try createMacDirectoryIfNeeded(for: job.localPath)
                    try await pullFile(device: session.device!, remotePath: job.remotePath, localPath: job.localPath)
                } else {
                    try await createAndroidDirectoryIfNeeded(device: session.device!, for: job.remotePath)
                    try await pushFile(device: session.device!, localPath: job.localPath, remotePath: job.remotePath)
                }
                
                filePollTask.cancel()
                session.finishCurrentFile()
                
                if session.isBackup {
                    let record = BackupFile(
                        deviceSerial: (session.device?.serial ?? ""),
                        sessionId: session.id,
                        relativePath: job.relativePath,
                        filename: URL(fileURLWithPath: job.relativePath).lastPathComponent,
                        size: job.size,
                        modifiedDate: job.modifiedDate,
                        sha256: nil, // Optional Hash verification later
                        transferDate: Date(),
                        destinationFolder: session.destination.path,
                        verificationStatus: "Unverified"
                    )
                    try? BackupRepository.shared.saveFile(record)
                }
                
            } catch {
                filePollTask.cancel()
                let errStr = error.localizedDescription
                print("Failed to transfer \(job.relativePath): \(errStr)")
                Task { @MainActor in
                    TransferTrace.logFailure(reason: "Transfer Exception", function: "processTransfer", error: errStr)
                }
                onProgress?(TransferProgress(sessionID: session.id, stage: .failed, errorMessage: errStr))
            }
        }
        
        session.cleanup()
        
        onProgress?(TransferProgress(sessionID: session.id, stage: .refreshing))
        
        await MainActor.run {
            session.state = .finished
            session.progress = 1.0
        }
        
        // Invalidate Caches for affected directories
        if session.direction == TransferDirection.androidToMac {
            await DirectoryCache.shared.invalidateMacCache(for: session.destination.path)
            let destParent = session.destination.pathComponents.dropLast().joined(separator: "/")
            let parentStr = destParent.isEmpty ? "/" : (destParent.hasPrefix("/") ? destParent : "/" + destParent)
            await DirectoryCache.shared.invalidateMacCache(for: parentStr)
        } else {
            await DirectoryCache.shared.invalidateAndroidCache(for: session.destination.path)
            let uniqueParentDirs = Set(plan.newJobs.map { ($0.relativePath as NSString).deletingLastPathComponent })
            for path in uniqueParentDirs {
                await DirectoryCache.shared.invalidateAndroidCache(for: (session.destination.path as NSString).appendingPathComponent(path))
            }
        }
        
        onProgress?(TransferProgress(sessionID: session.id, stage: .completed, percentage: 1.0, filesCompleted: session.copiedFiles + session.skippedFiles, totalFiles: session.totalFiles, bytesCopied: session.bytesCopied, totalBytes: session.totalBytesToCopy))
    }
    
    struct LocalFetchFile {
        let localPath: String
        let relativePath: String
        let size: Int64
        let modifiedDate: Date
    }
    
    private func fetchMacFileList(localURL: URL) throws -> [LocalFetchFile] {
        var files: [LocalFetchFile] = []
        let fileManager = FileManager.default
        var isDir: ObjCBool = false
        
        if fileManager.fileExists(atPath: localURL.path, isDirectory: &isDir) {
            if isDir.boolValue {
                let resourceKeys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
                guard let enumerator = fileManager.enumerator(at: localURL, includingPropertiesForKeys: resourceKeys) else {
                    return files
                }
                
                let parentDir = localURL.deletingLastPathComponent().path
                
                for case let fileURL as URL in enumerator {
                    let attributes = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                    var isDirectory: ObjCBool = false
                    fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
                    
                    if !isDirectory.boolValue {
                        let relativePath = fileURL.path.replacingOccurrences(of: parentDir + "/", with: "")
                        let size = Int64(attributes.fileSize ?? 0)
                        let date = attributes.contentModificationDate ?? Date()
                        files.append(LocalFetchFile(localPath: fileURL.path, relativePath: relativePath, size: size, modifiedDate: date))
                    }
                }
            } else {
                let attributes = try fileManager.attributesOfItem(atPath: localURL.path)
                let size = attributes[.size] as? Int64 ?? 0
                let date = attributes[.modificationDate] as? Date ?? Date()
                let relativePath = localURL.lastPathComponent
                files.append(LocalFetchFile(localPath: localURL.path, relativePath: relativePath, size: size, modifiedDate: date))
            }
        }
        return files
    }
    
    private func pullFile(device: AndroidDevice, remotePath: String, localPath: String) async throws {
        _ = try await ADBManager.shared.run(["-s", device.serial, "pull", remotePath, localPath])
    }
    
    private func pushFile(device: AndroidDevice, localPath: String, remotePath: String) async throws {
        let result = try await ADBManager.shared.runDetailed(["-s", device.serial, "push", localPath, remotePath])
        if result.exitCode != 0 {
            throw NSError(domain: "ADBError", code: Int(result.exitCode), userInfo: [NSLocalizedDescriptionKey: result.stderr.isEmpty ? "Failed to push file" : result.stderr])
        }
    }
    
    private func createMacDirectoryIfNeeded(for localPath: String) throws {
        let directory = URL(fileURLWithPath: localPath).deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    private var createdAndroidDirectories: Set<String> = []
    
    private func createAndroidDirectoryIfNeeded(device: AndroidDevice, for remotePath: String) async throws {
        let directory = (remotePath as NSString).deletingLastPathComponent
        if createdAndroidDirectories.contains(directory) { return }
        
        _ = try await ADBManager.shared.run(["-s", device.serial, "shell", "mkdir", "-p", "'\(directory)'"])
        createdAndroidDirectories.insert(directory)
    }
}
