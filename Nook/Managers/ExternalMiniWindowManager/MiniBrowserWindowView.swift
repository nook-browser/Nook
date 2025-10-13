import SwiftUI
import AppKit

struct MiniBrowserWindowView: View {
    let session: MiniWindowSession
    let adoptAction: () -> Void
    let dismissAction: () -> Void

    @State private var hostingWindow: NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            MiniWindowToolbar(session: session, adoptAction: adoptAction, window: hostingWindow)
            webContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .ignoresSafeArea(.container, edges: .top)
        .background(WindowAccessor { window in
            guard hostingWindow !== window else { return }
            hostingWindow = window
            window?.titlebarAppearsTransparent = true
            window?.titleVisibility = .hidden
            window?.titlebarSeparatorStyle = .none
        })
        .frame(minWidth: 640, minHeight: 480)
    }

    @ViewBuilder private var webContent: some View {
        if isRunningInPreviews {
            ZStack {
                LinearGradient(colors: [Color.black.opacity(0.08), Color.black.opacity(0.02)], startPoint: .top, endPoint: .bottom)
                VStack(spacing: 8) {
                    Image(systemName: "safari")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(.secondary)
                    Text("Web Content Placeholder")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.clear.opacity(0.08), lineWidth: 1)
                    .padding(8)
            )
            .background(Color.blue.opacity(0.3))
        } else {
            MiniWindowWebView(session: session)
        }
    }

    private var isRunningInPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        DispatchQueue.main.async {
            callback(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            callback(nsView.window)
        }
    }
}

#if DEBUG
#Preview {
    // Provide a mock session for preview
    let session = MiniWindowSession(
        url: URL(string: "https://apple.com")!,
        profile: nil,
        originName: "Preview",
        targetSpaceResolver: { "Preview Space" },
        adoptHandler: { _ in }
    )
    MiniBrowserWindowView(session: session, adoptAction: {}, dismissAction: {})
        .environmentObject(GradientColorManager())
}
#endif
