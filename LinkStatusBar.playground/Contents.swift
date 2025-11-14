import SwiftUI
import PlaygroundSupport

// MARK: - Color Hex Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a: UInt64
        let r: UInt64
        let g: UInt64
        let b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - LinkStatusBar Component
struct LinkStatusBar: View {
    let hoveredLink: String?
    let isCommandPressed: Bool
    
    var body: some View {
        if let link = hoveredLink, !link.isEmpty {
            Text(isCommandPressed ? "Open \(link) in a new tab and focus it" : link)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(hex: "3E4D2E"),
                            Color(hex: "2E2E2E")
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 999))
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .opacity(hoveredLink != nil && !hoveredLink!.isEmpty ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: hoveredLink)
        }
    }
}

// MARK: - Preview View
struct PreviewView: View {
    var body: some View {
        ZStack {
            // Dark background to see the status bar
            Color.black
                .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 20) {
                Text("LinkStatusBar Previews")
                    .font(.title)
                    .foregroundColor(.white)
                    .padding()
                
                VStack(alignment: .leading, spacing: 16) {
                    Text("Normal link hover:")
                        .foregroundColor(.white.opacity(0.7))
                    LinkStatusBar(
                        hoveredLink: "https://example.com/very/long/path/to/some/page",
                        isCommandPressed: false
                    )
                    
                    Text("Command pressed:")
                        .foregroundColor(.white.opacity(0.7))
                    LinkStatusBar(
                        hoveredLink: "https://github.com/user/repo",
                        isCommandPressed: true
                    )
                    
                    Text("Short URL:")
                        .foregroundColor(.white.opacity(0.7))
                    LinkStatusBar(
                        hoveredLink: "https://apple.com",
                        isCommandPressed: false
                    )
                    
                    Text("Hidden (no link):")
                        .foregroundColor(.white.opacity(0.7))
                    LinkStatusBar(
                        hoveredLink: nil,
                        isCommandPressed: false
                    )
                }
                .padding()
                
                Spacer()
            }
        }
        .frame(width: 600, height: 400)
    }
}

// MARK: - Set Live View
PlaygroundPage.current.setLiveView(PreviewView())

