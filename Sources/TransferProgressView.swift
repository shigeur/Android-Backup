import SwiftUI

struct TransferProgressView: View {
    @ObservedObject var service = TransferService.shared
    var onDismiss: (() -> Void)? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            switch service.state {
            case .idle:
                Text("Waiting to start...")
                    .foregroundColor(.secondary)
                    .padding(30)
                    
            case .scanning:
                VStack(spacing: 16) {
                    ProgressView("Scanning files...")
                    Text("Found \(service.totalFiles) items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(30)
                    
            case .preflight:
                DuplicateResolutionView(service: service)
                
            case .copying:
                copyingView
                
            case .finished:
                finishedView
                
            case .error(let msg):
                errorView(msg)
                
            case .verifying:
                ProgressView("Verifying files...")
                    .padding(30)
            }
        }
        .frame(width: 450)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
    }
    
    private var copyingView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Copying Files")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(URL(fileURLWithPath: service.currentFile).lastPathComponent)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                let currentFileTotal = formatBytes(service.currentFileSize)
                let currentFileCopied = formatBytes(service.currentFileBytesCopied)
                Text("\(currentFileCopied) / \(currentFileTotal)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                ProgressView(value: service.currentFileSize > 0 ? Double(service.currentFileBytesCopied) / Double(service.currentFileSize) : 0)
                    .tint(.blue)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            VStack(spacing: 12) {
                ProgressView(value: service.progress)
                    .tint(.blue)
                
                HStack {
                    Text("\(Int(service.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(service.copiedFiles + service.skippedFiles) / \(service.totalFiles) items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Total Data:")
                            .font(.caption)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Text("\(formatBytes(service.bytesCopied + service.currentFileBytesCopied)) / \(formatBytes(service.totalBytesToCopy))")
                            .font(.caption.monospacedDigit())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Speed:")
                            .font(.caption)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Text(formatSpeed(service.currentSpeedBytesPerSecond))
                            .font(.caption.monospacedDigit())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Time Remaining:")
                            .font(.caption)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Text(formatETA())
                            .font(.caption.monospacedDigit())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    service.cancel()
                }
            }
        }
        .padding(24)
    }
    
    private var finishedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 48))
            
            Text("Transfer Complete")
                .font(.title3.bold())
                
            VStack(alignment: .leading, spacing: 10) {
                InfoRow(label: "Copied:", value: "\(service.copiedFiles) files (\(formatBytes(service.bytesCopied)))")
                InfoRow(label: "Skipped:", value: "\(service.skippedFiles) files")
                InfoRow(label: "Avg Speed:", value: formatSpeed(service.currentSpeedBytesPerSecond))
                InfoRow(label: "Peak Speed:", value: formatSpeed(service.peakSpeedBytesPerSecond))
                InfoRow(label: "Time Taken:", value: formatDuration(service.elapsedTime))
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            Button("Done") {
                service.reset()
                onDismiss?()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
    }
    
    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 48))
                
            Text("Transfer Error")
                .font(.headline)
                
            Text(msg)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
            
            Button("Dismiss") {
                service.reset()
                onDismiss?()
            }
        }
        .padding(30)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatSpeed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec > 0 else { return "0 KB/s" }
        return formatBytes(Int64(bytesPerSec)) + "/s"
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }
    
    private func formatETA() -> String {
        let remainingBytes = Double(service.totalBytesToCopy) - Double(service.bytesCopied + service.currentFileBytesCopied)
        guard service.currentSpeedBytesPerSecond > 0, remainingBytes > 0 else { return "Calculating..." }
        let remainingSeconds = remainingBytes / service.currentSpeedBytesPerSecond
        return formatDuration(remainingSeconds)
    }
}
