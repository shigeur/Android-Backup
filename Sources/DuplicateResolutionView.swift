import SwiftUI

struct DuplicateResolutionView: View {
    @ObservedObject var session: TransferSession
    var onCancel: (() -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Transfer Plan")
                .font(.title2)
                .fontWeight(.bold)
            
            if let plan = session.transferPlan {
                VStack(spacing: 12) {
                    InfoRow(label: "New Files", value: "\(plan.newJobs.count)")
                    InfoRow(label: "Modified", value: "\(plan.modifiedJobs.count)")
                    
                    if !plan.duplicateJobs.isEmpty {
                        InfoRow(label: "Duplicates", value: "\(plan.duplicateJobs.count)")
                            .foregroundColor(.orange)
                    }
                    
                    Divider()
                    
                    InfoRow(label: "Transfer Size", value: formatBytes(plan.totalBytes))
                    if !plan.duplicateJobs.isEmpty {
                        InfoRow(label: "Skipped Size", value: formatBytes(plan.duplicateBytes))
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                if !plan.duplicateJobs.isEmpty {
                    Text("\(plan.duplicateJobs.count) duplicate files found. Choose an action:")
                        .font(.headline)
                        .padding(.top, 10)
                    
                    HStack(spacing: 16) {
                        Button("Skip Duplicates") {
                            Task { await TransferService.shared.executeTransfer(session: session, resolution: .skip) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!session.isScanComplete)
                        
                        Button("Replace All") {
                            Task { await TransferService.shared.executeTransfer(session: session, resolution: .replace) }
                        }
                        .disabled(!session.isScanComplete)
                        
                        Button("Cancel") {
                            onCancel?()
                        }
                        .foregroundColor(.red)
                    }
                } else {
                    HStack {
                        Spacer()
                        Button("Start Transfer") {
                            Task { await TransferService.shared.executeTransfer(session: session, resolution: .skip) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!session.isScanComplete)
                        
                        Button("Cancel") {
                            onCancel?()
                        }
                        Spacer()
                    }
                }
                
                if !session.isScanComplete {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Scanning remaining files in background...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 10)
                }
            } else {
                Text("Analyzing...")
            }
        }
        .padding()
        .touchBar {
            if let plan = session.transferPlan {
                if !plan.duplicateJobs.isEmpty {
                    Button(role: .cancel, action: { session.cancel(); TransferProgressPublisher.shared.removeSession(id: session.id) }) {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                    Button(action: { Task { await TransferService.shared.executeTransfer(session: session, resolution: .skip) } }) {
                        Label("Skip", systemImage: "forward.fill")
                    }
                    Button(action: { Task { await TransferService.shared.executeTransfer(session: session, resolution: .replace) } }) {
                        Label("Replace All", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(role: .cancel, action: { session.cancel(); TransferProgressPublisher.shared.removeSession(id: session.id) }) {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                    }
                    Button(action: { Task { await TransferService.shared.executeTransfer(session: session, resolution: .skip) } }) {
                        Label("Continue", systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
