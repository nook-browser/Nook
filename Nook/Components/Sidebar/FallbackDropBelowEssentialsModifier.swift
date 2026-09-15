import SwiftUI

/// No longer needed: every sidebar drop zone applies its own drop. Kept as a passthrough so
/// `SpacesSideBarView` compiles until it drops the call; delete in task Z.
struct FallbackDropBelowEssentialsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
