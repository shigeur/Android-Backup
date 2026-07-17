import SwiftUI

struct DuplicateResolutionView: View {
    @ObservedObject var service = TransferService.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Transfer Plan")
                .font(.title2)
                .fontWeight(.bold)
            
            if let plan = service.transferPlan {
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
                            Task { await service.executeTransfer(resolution: .skip) }
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Replace All") {
                            Task { await service.executeTransfer(resolution: .replace) }
                        }
                        
                        Button("Cancel") {
                            service.cancel()
                            service.reset()
                        }
                        .foregroundColor(.red)
                    }
                } else {
                    HStack {
                        Spacer()
                        Button("Start Transfer") {
                            Task { await service.executeTransfer(resolution: .skip) }
                        }
                        .buttonStyle(.borderedProminent)
                        
                        Button("Cancel") {
                            service.cancel()
                            service.reset()
                        }
                        Spacer()
                    }
                }
            } else {
                Text("Analyzing...")
            }
        }
        .padding()
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
