// Licensed under GPL-3.0. See LICENSE.
import SwiftUI
import AppKit

struct MiniBrowserWindowView: View {
    let session: MiniWindowSession

    var body: some View {
        webContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: .top)
            .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder private var webContent: some View {
        if isRunningInPreviews {
            ContentUnavailableView("Web Content Placeholder", systemImage: "safari")
        } else {
            MiniWindowWebView(session: session)
        }
    }

    private var isRunningInPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
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
    MiniBrowserWindowView(session: session)
        .environmentObject(GradientColorManager())
}
#endif
