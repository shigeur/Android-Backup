import SwiftUI

struct TransferProgressView: View {
    @ObservedObject var session: TransferSession
    var onDismiss: (() -> Void)? = nil
    
    @State private var showingCancelled = false
    
    private func triggerHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }
    
    private func handleCancel() {
        triggerHaptic()
        showingCancelled = true
        session.cancel()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            TransferProgressPublisher.shared.removeSession(id: session.id)
            onDismiss?()
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            switch session.state {
            case .idle:
                Text("Waiting to start...")
                    .foregroundColor(.secondary)
                    .padding(30)
                    
            case .scanning:
                scanningView
                    
            case .preflight:
                DuplicateResolutionView(session: session, onCancel: handleCancel)
                
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
        .touchBar {
            if showingCancelled {
                Text("Transfer Cancelled")
            } else {
                switch session.state {
                case .preflight:
                    if let plan = session.transferPlan, !plan.duplicateJobs.isEmpty {
                        Button("Skip Duplicates") {
                            triggerHaptic()
                            Task { await TransferService.shared.executeTransfer(session: session, resolution: .skip) }
                        }
                        .tint(.blue)
                        .accessibilityLabel("Skip Duplicates")
                        .accessibilityHint("Skips all duplicate files")
                        .accessibilityIdentifier("touchbar_skip")
                        
                        Button("Replace All") {
                            triggerHaptic()
                            Task { await TransferService.shared.executeTransfer(session: session, resolution: .replace) }
                        }
                        .disabled(!session.isScanComplete)
                        .accessibilityLabel("Replace All")
                        .accessibilityHint("Replaces all duplicate files")
                        .accessibilityIdentifier("touchbar_replace")
                        
                        Button("Cancel") {
                            handleCancel()
                        }
                        .tint(.red)
                        .accessibilityLabel("Cancel")
                        .accessibilityHint("Cancels the transfer")
                        .accessibilityIdentifier("touchbar_cancel")
                    } else {
                        Button("Cancel") {
                            handleCancel()
                        }
                        .tint(.red)
                    }
                    
                case .copying:
                    HStack(spacing: 8) {
                        Text("Copying...")
                        
                        ProgressView(value: session.overallProgress)
                            .progressViewStyle(.linear)
                            .frame(width: 100)
                            
                        Text("\(Int(session.overallProgress * 100))%")
                        
                        Text(formatSpeed(session.currentSpeedBytesPerSecond))
                        
                        Text(session.direction == .macToAndroid ? "Mac → Android" : "Android → Mac")
                        
                        if session.totalFiles > 1 {
                            Text("File \(session.copiedFiles + 1) of \(session.totalFiles)")
                        }
                        
                        Text(URL(fileURLWithPath: session.currentFile).lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: 150)
                            
                        Button("Cancel") {
                            handleCancel()
                        }
                        .tint(.red)
                        .accessibilityLabel("Cancel")
                        .accessibilityHint("Cancels the active transfer")
                        .accessibilityIdentifier("touchbar_cancel_active")
                    }
                    
                case .finished:
                    Button("Reveal in Finder") {
                        triggerHaptic()
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.destination.path)
                    }
                    .accessibilityLabel("Reveal in Finder")
                    .accessibilityHint("Opens the destination folder in Finder")
                    .accessibilityIdentifier("touchbar_reveal")
                    
                    Button("Done") {
                        triggerHaptic()
                        TransferProgressPublisher.shared.removeSession(id: session.id)
                        onDismiss?()
                    }
                    .tint(.blue)
                    .accessibilityLabel("Done")
                    .accessibilityHint("Closes the transfer dialog")
                    .accessibilityIdentifier("touchbar_done")
                    
                case .error(_):
                    Button("OK") {
                        triggerHaptic()
                        TransferProgressPublisher.shared.removeSession(id: session.id)
                        onDismiss?()
                    }
                    .tint(.blue)
                default:
                    EmptyView()
                }
            }
        }
    }
    
    private var scanningView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scanning Files...")
                .font(.headline)
            
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.blue)
                
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Files Found:")
                            .font(.caption)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Text("\(session.totalFiles)")
                            .font(.caption.monospacedDigit())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Estimated Size:")
                            .font(.caption)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Text("\(formatBytes(session.totalBytesFound))")
                            .font(.caption.monospacedDigit())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scan Speed:")
                            .font(.caption)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Text("\(Int(session.scanningSpeedItemsPerSecond)) items/s")
                            .font(.caption.monospacedDigit())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Elapsed:")
                            .font(.caption)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Text("\(formatDuration(session.elapsedTime))")
                            .font(.caption.monospacedDigit())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    handleCancel()
                }
            }
        }
        .padding(24)
    }
    
    private var copyingView: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // --- Current File Section ---
            VStack(alignment: .leading, spacing: 8) {
                Text("Current File")
                    .font(.headline)
                
                Text(URL(fileURLWithPath: session.currentFile).lastPathComponent)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                // Transfer Path
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.direction == .macToAndroid ? "Mac" : "Android")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text(URL(fileURLWithPath: session.direction == .macToAndroid ? session.currentLocalPath : session.currentRemotePath).deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Image(systemName: "arrow.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 2)
                    
                    Text(session.direction == .macToAndroid ? "Android" : "Mac")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text(URL(fileURLWithPath: session.direction == .macToAndroid ? session.currentRemotePath : session.currentLocalPath).deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.vertical, 4)
                
                let currentFileTotal = formatBytes(session.currentFileSize)
                let currentFileCopied = formatBytes(session.currentFileBytesCopied)
                
                HStack {
                    Text("\(currentFileCopied) / \(currentFileTotal)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(session.currentFileProgress * 100))%")
                        .font(.caption.monospacedDigit())
                }
                
                ProgressView(value: session.currentFileProgress)
                    .tint(.blue)
                    .animation(.linear(duration: 0.1), value: session.currentFileProgress)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            // --- Overall Transfer Section ---
            VStack(alignment: .leading, spacing: 8) {
                Text("Overall Transfer")
                    .font(.headline)
                
                HStack {
                    Text("\(session.copiedFiles + session.skippedFiles) / \(session.totalFiles) files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(session.overallProgress * 100))%")
                        .font(.caption.monospacedDigit())
                }
                
                ProgressView(value: session.overallProgress)
                    .tint(.blue)
                    .animation(.linear(duration: 0.1), value: session.overallProgress)
                
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Overall Bytes:")
                            .font(.caption)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Text("\(formatBytes(session.overallBytesTransferred)) / \(formatBytes(session.totalBytesToCopy))")
                            .font(.caption.monospacedDigit())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Speed:")
                            .font(.caption)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Text(formatSpeed(session.currentSpeedBytesPerSecond))
                            .font(.caption.monospacedDigit())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Average Speed:")
                            .font(.caption)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        let avgSpeed = session.elapsedTime > 0 ? Double(session.overallBytesTransferred) / session.elapsedTime : 0
                        Text(formatSpeed(avgSpeed))
                            .font(.caption.monospacedDigit())
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Estimated Remaining Time:")
                            .font(.caption)
                            .foregroundColor(Color(NSColor.tertiaryLabelColor))
                        Text(formatETA())
                            .font(.caption.monospacedDigit())
                    }
                }
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    handleCancel()
                }
            }
        }
        .padding(24)
        .onChange(of: session.currentFileProgress) { _ in
            let avgSpeed = session.elapsedTime > 0 ? Double(session.overallBytesTransferred) / session.elapsedTime : 0
            print("[Progress] Current: \(Int(session.currentFileProgress * 100))% | Overall: \(Int(session.overallProgress * 100))% | Current Bytes: \(formatBytes(session.currentFileBytesCopied)) | Overall Bytes: \(formatBytes(session.overallBytesTransferred)) | Speed: \(formatSpeed(session.currentSpeedBytesPerSecond)) | Avg: \(formatSpeed(avgSpeed)) | ETA: \(formatETA())")
        }
    }
    
    private var finishedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 48))
            
            Text("Transfer Complete")
                .font(.title3.bold())
                
            VStack(alignment: .leading, spacing: 10) {
                InfoRow(label: "Copied:", value: "\(session.copiedFiles) files (\(formatBytes(session.bytesCopied)))")
                InfoRow(label: "Skipped:", value: "\(session.skippedFiles) files")
                InfoRow(label: "Avg Speed:", value: formatSpeed(session.currentSpeedBytesPerSecond))
                InfoRow(label: "Peak Speed:", value: formatSpeed(session.peakSpeedBytesPerSecond))
                InfoRow(label: "Time Taken:", value: formatDuration(session.elapsedTime))
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            Button("Done") {
                TransferProgressPublisher.shared.removeSession(id: session.id)
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
                TransferProgressPublisher.shared.removeSession(id: session.id)
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
        let remainingBytes = Double(session.totalBytesToCopy) - Double(session.bytesCopied + session.currentFileBytesCopied)
        guard session.currentSpeedBytesPerSecond > 0, remainingBytes > 0 else { return "Calculating..." }
        let remainingSeconds = remainingBytes / session.currentSpeedBytesPerSecond
        return formatDuration(remainingSeconds)
    }
}
