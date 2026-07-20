import SwiftUI

struct ConnectionBannerData: Equatable {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let id = UUID()
}

struct ConnectionBannerView: View {
    let data: ConnectionBannerData
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: data.icon)
                .font(.system(size: 24))
                .foregroundColor(data.color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(data.title)
                    .font(.headline)
                
                if !data.subtitle.isEmpty {
                    Text(data.subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
        .padding()
        .frame(width: 350)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
    }
}

struct ConnectionBannerModifier: ViewModifier {
    @State private var bannerData: ConnectionBannerData?
    @State private var isVisible: Bool = false
    @State private var hideTask: Task<Void, Never>?
    @ObservedObject var deviceLifecycle = DeviceLifecycleManager.shared
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            
            if isVisible, let data = bannerData {
                ConnectionBannerView(data: data)
                    .padding(.top, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(100)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isVisible)
        .onChange(of: deviceLifecycle.state) { newState in
            handleStateChange(newState)
        }
    }
    
    private func handleStateChange(_ state: DeviceConnectionState) {
        var newData: ConnectionBannerData?
        
        switch state {
        case .ready(let device):
            print("[UI] Connection Banner Presented: Connected")
            newData = ConnectionBannerData(
                title: "\(device.model) Connected",
                subtitle: "Ready for file transfer.",
                icon: "circle.fill",
                color: .green
            )
        case .disconnected:
            print("[UI] Connection Banner Presented: Disconnected")
            newData = ConnectionBannerData(
                title: "Device Disconnected",
                subtitle: "Waiting for Android device...",
                icon: "circle.fill",
                color: .gray
            )
        case .adbMissing:
            print("[UI] Connection Banner Presented: ADB Missing")
            newData = ConnectionBannerData(
                title: "Android Platform Tools Not Found",
                subtitle: "Install Android Platform Tools to continue.",
                icon: "exclamationmark.triangle.fill",
                color: .orange
            )
        default:
            break
        }
        
        if let newData = newData {
            showBanner(newData)
        }
    }
    
    private func showBanner(_ data: ConnectionBannerData) {
        hideTask?.cancel()
        
        bannerData = data
        isVisible = true
        
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    isVisible = false
                    print("[UI] Connection Banner Dismissed")
                }
            }
        }
    }
}

extension View {
    func connectionBanner() -> some View {
        self.modifier(ConnectionBannerModifier())
    }
}
