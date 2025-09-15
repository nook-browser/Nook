import SwiftUI

struct MiniBrowserWindowView: View {
    let session: MiniWindowSession
    let adoptAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MiniWindowToolbar(session: session, adoptAction: adoptAction)
            Divider()
            MiniWindowWebView(session: session)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 640, minHeight: 480)
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
}
#endif
