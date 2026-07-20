import SwiftUI

struct DiagnosticPanelView: View {
    @ObservedObject var logger = DiagnosticLogger.shared
    @ObservedObject var appCoordinator = ApplicationStartupCoordinator.shared
    @ObservedObject var deviceLifecycle = DeviceLifecycleManager.shared
    @ObservedObject var fileOperation = FileOperationService.shared
    @ObservedObject var clipboard = ClipboardManager.shared
    @ObservedObject var transferService = TransferService.shared
    @ObservedObject var uiState = UIStateManager.shared
    
    @State private var selectedCategory: LogCategory = .all
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Developer Diagnostic Panel")
                .font(.title2)
                .bold()
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            HSplitView {
                // Left Column: State Inspection
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        runtimeStateSection
                        Divider()
                        deviceInformationSection
                        Divider()
                        transferInformationSection
                    }
                    .padding()
                }
                .frame(minWidth: 300, idealWidth: 350)
                
                // Right Column: Event Timeline
                VStack(spacing: 0) {
                    HStack {
                        Text("Event Timeline")
                            .font(.headline)
                        Spacer()
                        Picker("Filter", selection: $selectedCategory) {
                            ForEach(LogCategory.allCases) { category in
                                Text(category.rawValue).tag(category)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 150)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    
                    Divider()
                    
                    List {
                        ForEach(filteredEvents) { event in
                            HStack(alignment: .top) {
                                Text(event.formattedTime)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 70, alignment: .leading)
                                
                                Text("[\(event.category.rawValue)]")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(colorForCategory(event.category))
                                    .frame(width: 80, alignment: .leading)
                                
                                Text(event.message)
                                    .font(.system(.body, design: .monospaced))
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    
                    Divider()
                    
                    Button("Copy Diagnostic Report") {
                        copyDiagnosticReport()
                    }
                    .padding()
                }
                .frame(minWidth: 400, idealWidth: 500)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
    
    // MARK: - Sections
    
    private var runtimeStateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Runtime State").font(.headline)
            Group {
                labeledValue("App State", "\(appCoordinator.state)")
                labeledValue("Device State", "\(deviceLifecycle.state)")
                labeledValue("File Operation", fileOperation.isOperating ? "Operating (\(Int(fileOperation.operationProgress * 100))%)" : "Idle")
                labeledValue("Focused Pane", uiState.focusedPane.rawValue)
                labeledValue("Clipboard Items", "\(clipboard.currentItem?.paths.count ?? 0)")
            }
        }
    }
    
    private var deviceInformationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Device Information").font(.headline)
            if case .ready(let device) = deviceLifecycle.state {
                labeledValue("Name", device.model)
                labeledValue("Serial", device.serial)
                labeledValue("Authorization", device.status)
            } else if case .connected(let device) = deviceLifecycle.state {
                labeledValue("Serial", device.serial)
                labeledValue("Status", device.status)
            } else {
                Text("No device connected").foregroundColor(.secondary)
            }
        }
    }
    
    private var transferInformationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Transfer Information").font(.headline)
            labeledValue("Status", "\(transferService.state)")
            if let plan = transferService.transferPlan {
                labeledValue("Direction", plan.direction == .androidToMac ? "Android -> Mac" : "Mac -> Android")
                labeledValue("Dest Path", plan.destination.path)
                labeledValue("Stats", "\(plan.newJobs.count) New | \(plan.modifiedJobs.count) Mod | \(plan.duplicateJobs.count) Dup")
            }
            if transferService.state == .copying || transferService.state == .scanning || transferService.state == .preflight {
                labeledValue("Progress", "\(Int(transferService.progress * 100))%")
                labeledValue("Bytes", "\(transferService.bytesCopied) / \(transferService.totalBytesToCopy)")
                labeledValue("Current File", transferService.currentFile)
            }
        }
    }
    
    // MARK: - Helpers
    
    private var filteredEvents: [DiagnosticEvent] {
        if selectedCategory == .all {
            return logger.events.reversed()
        }
        return logger.events.filter { $0.category == selectedCategory }.reversed()
    }
    
    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text("\(label):")
                .fontWeight(.semibold)
                .frame(width: 120, alignment: .trailing)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
    
    private func colorForCategory(_ category: LogCategory) -> Color {
        switch category {
        case .device: return .blue
        case .transfer: return .purple
        case .clipboard: return .orange
        case .filesystem: return .green
        case .adb: return .red
        case .directory: return .cyan
        case .ui: return .pink
        case .all: return .primary
        }
    }
    
    private func copyDiagnosticReport() {
        var report = "=== ANDROID BACKUP DIAGNOSTIC REPORT ===\n\n"
        report += "Date: \(Date())\n"
        report += "App State: \(appCoordinator.state)\n"
        report += "Device State: \(deviceLifecycle.state)\n"
        report += "Focused Pane: \(uiState.focusedPane.rawValue)\n"
        report += "Clipboard Action: \(clipboard.currentItem?.action == .copy ? "Copy" : (clipboard.currentItem?.action == .cut ? "Cut" : "None"))\n"
        report += "Clipboard Count: \(clipboard.currentItem?.paths.count ?? 0)\n"
        report += "Transfer State: \(transferService.state)\n\n"
        
        report += "=== EVENT TIMELINE ===\n"
        for event in logger.events {
            report += "[\(event.formattedTime)] [\(event.category.rawValue)] \(event.message)\n"
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }
}
