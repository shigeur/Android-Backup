import SwiftUI

struct SmartSyncView: View {
    let device: AndroidDevice
    let localURL: URL
    let remotePath: String
    @Binding var isPresented: Bool
    
    @State private var isAnalyzing = true
    @State private var plan: SyncPlan?
    @ObservedObject var progressPublisher = TransferProgressPublisher.shared
    
    struct SyncPlan {
        var toPull: [ADBFile] = []
        var toPush: [LocalFileItem] = []
        var identicalCount: Int = 0
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Smart Sync")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Syncing:")
            Text("Android: \(remotePath)")
                .font(.caption)
            Text("Mac: \(localURL.path)")
                .font(.caption)
            
            Divider()
            
            if isAnalyzing {
                ProgressView("Analyzing differences...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let plan = plan {
                VStack(spacing: 15) {
                    InfoRow(label: "Identical Files", value: "\(plan.identicalCount)")
                        .foregroundColor(.secondary)
                    
                    InfoRow(label: "To Pull (Android -> Mac)", value: "\(plan.toPull.count) files")
                    InfoRow(label: "To Push (Mac -> Android)", value: "\(plan.toPush.count) files")
                    
                    Spacer()
                    
                    HStack(spacing: 20) {
                        Button("Cancel") {
                            isPresented = false
                        }
                        
                        Button("Execute Sync") {
                            executeSync(plan: plan)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(plan.toPull.isEmpty && plan.toPush.isEmpty)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(30)
        .frame(width: 500, height: 400)
        .onAppear {
            analyze()
        }
    }
    
    private func analyze() {
        isAnalyzing = true
        Task {
            let directoryService = DirectoryService(device: device)
            let localService = LocalDirectoryService.shared
            
            do {
                let remoteFiles = try await directoryService.listDirectory(remotePath)
                let localFiles = try localService.listDirectory(localURL)
                
                // Exclude directories for simplistic file sync
                let rFiles = remoteFiles.filter { !$0.isDirectory }
                let lFiles = localFiles.filter { !$0.isDirectory }
                
                let localDict = Dictionary(uniqueKeysWithValues: lFiles.map { ($0.name, $0) })
                let remoteDict = Dictionary(uniqueKeysWithValues: rFiles.map { ($0.name, $0) })
                
                var p = SyncPlan()
                
                // Find files on remote not on local, or modified
                for rFile in rFiles {
                    if let lFile = localDict[rFile.name] {
                        if rFile.size == lFile.size {
                            p.identicalCount += 1
                        } else {
                            // Size differs, assume modified, let's pull it (Remote usually wins for backups)
                            p.toPull.append(rFile)
                        }
                    } else {
                        // New on remote
                        p.toPull.append(rFile)
                    }
                }
                
                // Find files on local not on remote
                for lFile in lFiles {
                    if remoteDict[lFile.name] == nil {
                        p.toPush.append(lFile)
                    }
                }
                
                self.plan = p
                self.isAnalyzing = false
                
            } catch {
                print("Failed to analyze: \(error)")
                self.isAnalyzing = false
            }
        }
    }
    
    private func executeSync(plan: SyncPlan) {
        // We will just issue two transfers sequentially or one if only one direction
        isPresented = false
        
        let task = Task {
            if !plan.toPull.isEmpty {
                let session = TransferProgressPublisher.shared.createSession(device: device, direction: .androidToMac, destination: localURL, isBackup: false)
                await TransferService.shared.prepareTransfer(session: session, sourcePaths: plan.toPull.map { $0.path }, duplicateMode: .fast)
                await TransferService.shared.executeTransfer(session: session, resolution: .replace)
            }
            
            if !plan.toPush.isEmpty {
                let session = TransferProgressPublisher.shared.createSession(device: device, direction: .macToAndroid, destination: URL(fileURLWithPath: remotePath), isBackup: false)
                await TransferService.shared.prepareTransfer(session: session, sourcePaths: plan.toPush.map { $0.url.path }, duplicateMode: .fast)
                await TransferService.shared.executeTransfer(session: session, resolution: .replace)
            }
        }
        progressPublisher.activeSessions.values.first?.setActiveTask(task)
    }
}
