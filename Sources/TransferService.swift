import Foundation
import Combine

enum TransferDirection {
    case androidToMac
    case macToAndroid
}

enum TransferState: Equatable {
    case idle
    case scanning
    case preflight
    case copying
    case verifying
    case finished
    case error(String)
}

enum DuplicateDetectionMode: String, CaseIterable {
    case fast = "Fast"
    case balanced = "Balanced"
    case safe = "Safe (SHA-256)"
}

enum DuplicateResolution {
    case skip
    case replace
    case rename
}

struct TransferPlan {
    let device: AndroidDevice
    let direction: TransferDirection
    let destination: URL
    let isBackup: Bool
    
    var newJobs: [TransferJob] = []
    var modifiedJobs: [TransferJob] = []
    var duplicateJobs: [TransferJob] = []
    
    var totalBytes: Int64 = 0
    var duplicateBytes: Int64 = 0
    var skippedBytes: Int64 = 0
}

struct RemoteFile {
    let path: String
    let relativePath: String
    let size: Int64
    let modifiedDate: Date
}

struct TransferJob {
    let remotePath: String
    let localPath: String
    let relativePath: String
    let size: Int64
    let modifiedDate: Date
}

@MainActor
class TransferService: ObservableObject {
    static let shared = TransferService()
    
    @Published var state: TransferState = .idle
    @Published var totalFiles: Int = 0
    @Published var copiedFiles: Int = 0
    @Published var skippedFiles: Int = 0
    @Published var currentFile: String = ""
    @Published var progress: Double = 0.0
    
    // Stats
    @Published var bytesCopied: Int64 = 0
    @Published var totalBytesToCopy: Int64 = 0
    @Published var currentSpeedBytesPerSecond: Double = 0.0
    
    @Published var transferPlan: TransferPlan? = nil
    
    // Detailed Progress
    @Published var elapsedTime: TimeInterval = 0
    @Published var currentFileSize: Int64 = 0
    @Published var currentFileBytesCopied: Int64 = 0
    @Published var peakSpeedBytesPerSecond: Double = 0.0
    
    private var isCancelled = false
    private var progressTimer: AnyCancellable?
    
    private init() {}
    
    func cancel() {
        isCancelled = true
    }
    
    func reset() {
        state = .idle
        totalFiles = 0
        copiedFiles = 0
        skippedFiles = 0
        currentFile = ""
        progress = 0.0
        bytesCopied = 0
        totalBytesToCopy = 0
        currentSpeedBytesPerSecond = 0.0
        peakSpeedBytesPerSecond = 0.0
        elapsedTime = 0
        currentFileSize = 0
        currentFileBytesCopied = 0
        isCancelled = false
        transferPlan = nil
        progressTimer?.cancel()
        progressTimer = nil
    }
    
    func prepareTransfer(
        device: AndroidDevice,
        direction: TransferDirection,
        sourcePaths: [String],
        destination: URL,
        isBackup: Bool = false,
        duplicateMode: DuplicateDetectionMode = .fast
    ) async {
        isCancelled = false
        state = .scanning
        
        do {
            var allJobs: [TransferJob] = []
            var plan = TransferPlan(device: device, direction: direction, destination: destination, isBackup: isBackup)
            
            if direction == .androidToMac {
                for path in sourcePaths {
                    let files = try await fetchAndroidFileList(device: device, remotePath: path)
                    for file in files {
                        let relativePath = file.relativePath
                        let destFileURL = destination.appendingPathComponent(relativePath)
                        allJobs.append(TransferJob(remotePath: file.path, localPath: destFileURL.path, relativePath: relativePath, size: file.size, modifiedDate: file.modifiedDate))
                    }
                }
            } else {
                for path in sourcePaths {
                    let localURL = URL(fileURLWithPath: path)
                    let files = try fetchMacFileList(localURL: localURL)
                    for file in files {
                        let relativePath = file.relativePath
                        let remoteDestPath = (destination.path as NSString).appendingPathComponent(relativePath)
                        allJobs.append(TransferJob(remotePath: remoteDestPath, localPath: file.localPath, relativePath: relativePath, size: file.size, modifiedDate: file.modifiedDate))
                    }
                }
            }
            
            // Check existence for duplicate detection
            for job in allJobs {
                var isDuplicate = false
                var isModified = false
                
                if direction == .androidToMac {
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
                    // macToAndroid
                    // Simplistic check for now, ideally we'd stat the specific file
                    // But to avoid N network calls, we consider it new unless Backup DB knows it, or we do a batch stat.
                    // For now, use the DB if available, otherwise assume new (Mode 1 Fast without extra ADB overhead).
                    if let record = try? DatabaseManager.shared.getRecord(deviceSerial: device.serial, relativePath: job.relativePath) {
                        if record.size == job.size {
                            isDuplicate = true
                        } else {
                            isModified = true
                        }
                    }
                }
                
                if isDuplicate {
                    plan.duplicateJobs.append(job)
                    plan.duplicateBytes += job.size
                } else if isModified {
                    plan.modifiedJobs.append(job)
                    plan.totalBytes += job.size
                } else {
                    plan.newJobs.append(job)
                    plan.totalBytes += job.size
                }
            }
            
            self.transferPlan = plan
            self.state = .preflight
            
        } catch {
            self.state = .error(error.localizedDescription)
        }
    }
    
    func executeTransfer(resolution: DuplicateResolution) async {
        guard let plan = transferPlan else { return }
        
        state = .copying
        let startTime = Date()
        
        var filesToTransfer: [TransferJob] = plan.newJobs + plan.modifiedJobs
        
        if resolution == .replace {
            filesToTransfer.append(contentsOf: plan.duplicateJobs)
            totalBytesToCopy = plan.totalBytes + plan.duplicateBytes
            skippedFiles = 0
        } else {
            // skip duplicates
            totalBytesToCopy = plan.totalBytes
            skippedFiles = plan.duplicateJobs.count
        }
        
        totalFiles = plan.newJobs.count + plan.modifiedJobs.count + plan.duplicateJobs.count
        copiedFiles = 0
        bytesCopied = 0
        elapsedTime = 0
        
        // Start Progress Timer
        progressTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self = self else { return }
            self.elapsedTime = Date().timeIntervalSince(startTime)
            if self.elapsedTime > 0 {
                let totalCurrentBytes = self.bytesCopied + self.currentFileBytesCopied
                self.currentSpeedBytesPerSecond = Double(totalCurrentBytes) / self.elapsedTime
                if self.currentSpeedBytesPerSecond > self.peakSpeedBytesPerSecond {
                    self.peakSpeedBytesPerSecond = self.currentSpeedBytesPerSecond
                }
            }
        }
        
        for job in filesToTransfer {
            if isCancelled { break }
            
            currentFile = job.relativePath
            currentFileSize = job.size
            currentFileBytesCopied = 0
            progress = Double(copiedFiles + skippedFiles) / Double(totalFiles)
            
            // For Android to Mac, we can poll the local file size to update currentFileBytesCopied
            var filePollTimer: AnyCancellable? = nil
            if plan.direction == .androidToMac {
                filePollTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                    guard let self = self else { return }
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: job.localPath),
                       let currentSize = attrs[.size] as? Int64 {
                        self.currentFileBytesCopied = min(currentSize, job.size)
                    }
                }
            } else {
                // For Mac to Android, simulate progress or just leave it at 0 until done,
                // or we could interpolate. Simple interpolation:
                filePollTimer = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                    guard let self = self else { return }
                    if self.currentSpeedBytesPerSecond > 0 {
                        let newCopied = self.currentFileBytesCopied + Int64(self.currentSpeedBytesPerSecond * 0.2)
                        self.currentFileBytesCopied = min(newCopied, job.size)
                    }
                }
            }
            
            do {
                if plan.direction == .androidToMac {
                    try createMacDirectoryIfNeeded(for: job.localPath)
                    try await pullFile(device: plan.device, remotePath: job.remotePath, localPath: job.localPath)
                } else {
                    try await createAndroidDirectoryIfNeeded(device: plan.device, for: job.remotePath)
                    try await pushFile(device: plan.device, localPath: job.localPath, remotePath: job.remotePath)
                }
                
                filePollTimer?.cancel()
                currentFileBytesCopied = job.size // Ensure it reaches 100%
                
                if plan.isBackup {
                    let record = FileRecord(
                        deviceSerial: plan.device.serial,
                        relativePath: job.relativePath,
                        filename: URL(fileURLWithPath: job.relativePath).lastPathComponent,
                        size: job.size,
                        modifiedDate: job.modifiedDate,
                        sha256: nil, // Optional Hash verification later
                        transferDate: Date(),
                        destinationFolder: plan.destination.path,
                        verificationStatus: "Unverified"
                    )
                    try? DatabaseManager.shared.saveRecord(record)
                }
                
                copiedFiles += 1
                bytesCopied += job.size
                currentFileBytesCopied = 0 // Reset for next file
                
                let elapsed = Date().timeIntervalSince(startTime)
                if elapsed > 0 {
                    currentSpeedBytesPerSecond = Double(bytesCopied) / elapsed
                }
            } catch {
                filePollTimer?.cancel()
                // Log and continue, or fail the whole thing
                print("Failed to transfer \(job.relativePath): \(error)")
            }
        }
        
        progressTimer?.cancel()
        progressTimer = nil
        
        state = .finished
        progress = 1.0
        
        // Invalidate Caches for affected directories
        if plan.direction == .androidToMac {
            await DirectoryCache.shared.invalidateMacCache(for: plan.destination.path)
            let destParent = plan.destination.pathComponents.dropLast().joined(separator: "/")
            let parentStr = destParent.isEmpty ? "/" : (destParent.hasPrefix("/") ? destParent : "/" + destParent)
            await DirectoryCache.shared.invalidateMacCache(for: parentStr)
        } else {
            await DirectoryCache.shared.invalidateAndroidCache(for: plan.destination.path)
        }
    }
    
    private func fetchAndroidFileList(device: AndroidDevice, remotePath: String) async throws -> [RemoteFile] {
        let isDirCommand = ["-s", device.serial, "shell", "if [ -d '\(remotePath)' ]; then echo 'DIR'; else echo 'FILE'; fi"]
        let isDirResult = try await ADBManager.shared.run(isDirCommand)
        let isDirectory = isDirResult.trimmingCharacters(in: .whitespacesAndNewlines) == "DIR"
        
        let searchPath = isDirectory ? remotePath : remotePath
        
        let command = ["-s", device.serial, "shell", "find", "'\(searchPath)'", "-type", "f", "-exec", "stat", "-c", "'%s||%Y||%n'", "{}", "\\;"]
        let result = try await ADBManager.shared.runDetailed(command)
        
        var files: [RemoteFile] = []
        let lines = result.stdout.components(separatedBy: .newlines)
        
        let remotePathName = (remotePath as NSString).lastPathComponent
        
        for line in lines {
            if line.isEmpty || line.contains("find: ") || line.contains("stat: ") { continue }
            
            let parts = line.components(separatedBy: "||")
            guard parts.count >= 3 else { continue }
            
            if let size = Int64(parts[0].trimmingCharacters(in: .whitespaces)), let mtime = TimeInterval(parts[1].trimmingCharacters(in: .whitespaces)) {
                let fullPath = parts[2...].joined(separator: "||").trimmingCharacters(in: .whitespaces)
                
                var relativePath = ""
                if isDirectory {
                    // Extract relative to the directory itself
                    // If remotePath is /sdcard/DCIM and fullPath is /sdcard/DCIM/Camera/a.jpg
                    // relative path should be DCIM/Camera/a.jpg
                    let parentDir = (remotePath as NSString).deletingLastPathComponent
                    if parentDir != "/" {
                        relativePath = fullPath.replacingOccurrences(of: parentDir + "/", with: "")
                    } else {
                        relativePath = fullPath.replacingOccurrences(of: "/", with: "")
                    }
                } else {
                    relativePath = remotePathName
                }
                
                files.append(RemoteFile(path: fullPath, relativePath: relativePath, size: size, modifiedDate: Date(timeIntervalSince1970: mtime)))
            }
        }
        
        return files
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
        _ = try await ADBManager.shared.run(["-s", device.serial, "push", localPath, remotePath])
    }
    
    private func createMacDirectoryIfNeeded(for localPath: String) throws {
        let directory = URL(fileURLWithPath: localPath).deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    private func createAndroidDirectoryIfNeeded(device: AndroidDevice, for remotePath: String) async throws {
        let directory = (remotePath as NSString).deletingLastPathComponent
        _ = try await ADBManager.shared.run(["-s", device.serial, "shell", "mkdir", "-p", "'\(directory)'"])
    }
}
