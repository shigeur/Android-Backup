import SwiftUI

struct DebugConsoleView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var logger = DebugLogger.shared
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Developer Debug Console")
                    .font(.title2)
                    .bold()
                
                Spacer()
                
                Button("Export to Desktop") {
                    exportDebugLog()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            Form {
                Section(header: Text("Last Operation Summary")) {
                    InfoRow(label: "Directory", value: logger.lastDirectory)
                    InfoRow(label: "Command", value: logger.lastCommand)
                    InfoRow(label: "Exit Code", value: "\(logger.lastExitCode)")
                    InfoRow(label: "Time (ms)", value: "\(logger.lastExecutionTimeMs) ms")
                    InfoRow(label: "Files Parsed", value: "\(logger.lastFilesParsed)")
                    InfoRow(label: "ViewModel UI Rows", value: "\(logger.lastViewModelRows)")
                    InfoRow(label: "Is Loading", value: "\(logger.lastIsLoading)")
                    InfoRow(label: "Error State", value: logger.lastError)
                }
                
                Section(header: Text("Raw stdout")) {
                    TextEditor(text: .constant(logger.lastStdout))
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 100, maxHeight: 200)
                }
                
                Section(header: Text("Raw stderr")) {
                    TextEditor(text: .constant(logger.lastStderr))
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 50, maxHeight: 100)
                        .foregroundColor(logger.lastStderr.isEmpty ? .secondary : .red)
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            Text("Recent Operations Log")
                .font(.headline)
            
            List(logger.logs.reversed()) { log in
                VStack(alignment: .leading) {
                    Text(log.command)
                        .font(.system(.caption, design: .monospaced))
                        .bold()
                    HStack {
                        Text("\(log.timestamp, style: .time)")
                        Text("Exit: \(log.exitCode)")
                            .foregroundColor(log.exitCode == 0 ? .green : .red)
                        Text("\(log.executionTimeMs) ms")
                        Spacer()
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                }
            }
            .textSelection(.enabled)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction) // Matches ESC
                .buttonStyle(.borderedProminent)
                
                // Invisible button to capture Cmd+W
                Button("") {
                    dismiss()
                }
                .keyboardShortcut("w", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(minWidth: 500, minHeight: 600)
    }
    
    private func exportDebugLog() {
        let logString = """
        Debug Log - \(Date())
        Directory: \(logger.lastDirectory)
        Command: \(logger.lastCommand)
        Exit Code: \(logger.lastExitCode)
        Execution Time: \(logger.lastExecutionTimeMs) ms
        Files Parsed: \(logger.lastFilesParsed)
        ViewModel Rows: \(logger.lastViewModelRows)
        Is Loading: \(logger.lastIsLoading)
        Error State: \(logger.lastError)
        
        ---- STDOUT ----
        \(logger.lastStdout)
        
        ---- STDERR ----
        \(logger.lastStderr)
        """
        
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("AndroidBackupDebug.txt")
        
        do {
            try logString.write(to: url, atomically: true, encoding: .utf8)
            // Open the file with default text editor
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [url.path]
            try task.run()
        } catch {
            print("Failed to export debug log: \(error)")
        }
    }
}
