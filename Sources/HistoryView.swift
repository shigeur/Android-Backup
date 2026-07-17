import SwiftUI

struct HistoryView: View {
    // In a real app, this would fetch from DatabaseManager
    // For now we use static data for the mockup
    let history: [BackupSession] = [
        BackupSession(date: Date(), size: 186_000_000_000, files: 52391, duration: 21*60 + 18, status: "Success"),
        BackupSession(date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!, size: 4_200_000_000, files: 523, duration: 2*60 + 44, status: "Success")
    ]
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("Backup History")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.bottom)
            
            List(history) { session in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(session.date, style: .date)
                            .font(.headline)
                        Spacer()
                        Text(session.status)
                            .foregroundColor(.green)
                            .fontWeight(.bold)
                    }
                    
                    HStack(spacing: 20) {
                        Label(formatBytes(session.size), systemImage: "externaldrive")
                        Label("\(session.files) files", systemImage: "doc.on.doc")
                        Label(formatDuration(session.duration), systemImage: "clock")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            .listStyle(.inset)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(seconds)) ?? ""
    }
}

struct BackupSession: Identifiable {
    let id = UUID()
    let date: Date
    let size: Int64
    let files: Int
    let duration: Int
    let status: String
}
