import SwiftUI

extension View {
    
    /// Measures the geometry of the attached view.
    func measure(_ size: Binding<CGSize>) -> some View {
        self.background {
            GeometryReader { reader in
                Color.clear.preference(
                    key: ViewSizePreferenceKey.self,
                    value: reader.size
                )
            }
        }
        .onPreferenceChange(ViewSizePreferenceKey.self) {
            size.wrappedValue = $0 ?? .zero
        }
    }
}

struct ViewSizePreferenceKey: PreferenceKey {
    
    static func reduce(value: inout CGSize?, nextValue: () -> CGSize?) {
        value = nextValue() ?? value
    }
    
    static var defaultValue: CGSize? = nil
}
