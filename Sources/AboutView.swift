import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) var openURL
    
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 128, height: 128)
            
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Android Backup")
                        .font(.system(size: 28, weight: .bold))
                    Text("Version Beta-1 Stable")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                Text("Professional Android file manager and backup utility for macOS.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Designed and developed by Ninos.")
                    Text("Development assisted by Google Antigravity AI.")
                    Text("Built using SwiftUI, AppKit, SQLite (GRDB), and Android Platform Tools (ADB).")
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
                
                HStack(spacing: 16) {
                    Button("GitHub Repository") {
                        openURL(URL(string: "https://github.com/placeholder")!)
                    }
                    Button("Website") {
                        openURL(URL(string: "https://example.com")!)
                    }
                    Button("Support") {
                        openURL(URL(string: "mailto:support@example.com")!)
                    }
                }
                .buttonStyle(.link)
                .font(.system(size: 12))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Source (MIT License)")
                    Text("© 2026 Ninos. All rights reserved.")
                }
                .font(.system(size: 10))
                .foregroundColor(Color(NSColor.tertiaryLabelColor))
                .padding(.top, 4)
            }
        }
        .padding(30)
        .frame(width: 500)
        .fixedSize()
    }
}
