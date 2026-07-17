import SwiftUI

struct SettingsView: View {
    @ObservedObject var adbManager = ADBManager.shared
    @AppStorage("isDarkMode") private var isDarkMode = false
    @AppStorage("parallelWorkers") private var parallelWorkers: Int = 1
    @AppStorage("manualAdbPath") private var manualAdbPath: String = ""
    @State private var showingDebugConsole = false
    @State private var showingConnectionDiagnostics = false
    
    var body: some View {
        Form {
            Section(header: Text("ADB Configuration").font(.headline)) {
                HStack {
                    Text("ADB Path:")
                    TextField("e.g. /opt/homebrew/bin/adb", text: $manualAdbPath)
                        .textFieldStyle(.roundedBorder)
                }
                Text("Ensure you have Platform Tools installed. Enter the path to your ADB executable if it's not in a standard location.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom)
            
            Section(header: Text("Developer").font(.headline)) {
                Button("Open Debug Console") {
                    showingDebugConsole = true
                }
                Button("Connection Diagnostics") {
                    showingConnectionDiagnostics = true
                }
            }
            .padding(.bottom)
            .sheet(isPresented: $showingDebugConsole) {
                DebugConsoleView()
            }
            .sheet(isPresented: $showingConnectionDiagnostics) {
                ConnectionDiagnosticsView()
            }
            
            Section(header: Text("Transfer Settings").font(.headline)) {
                Picker("Parallel Workers", selection: $parallelWorkers) {
                    Text("1 (Safe/Sequential)").tag(1)
                    Text("2").tag(2)
                    Text("4").tag(4)
                    Text("8 (Fastest/High Load)").tag(8)
                }
                .pickerStyle(.segmented)
                
                Text("Using multiple workers can speed up small file transfers, but might overwhelm the Android storage if the device is slow.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom)
            
            Section(header: Text("Appearance").font(.headline)) {
                Toggle("Force Dark Mode", isOn: $isDarkMode)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
