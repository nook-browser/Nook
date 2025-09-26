import SwiftUI

/// An example of how to use page view with a ForEach structure. 
struct PageViewForEachExample: View {
    
    @State private var selection: Int = 1
    
    var body: some View {
        PageView(selection: $selection) {
            ForEach(1...10, id: \.self) { value in
                ExamplePage(value: value)
            }
        }
    }
}

// MARK: - Preview

struct PageViewForEachExample_Previews: PreviewProvider {
    
    static var previews: some View {
        PageViewForEachExample()
            .pageViewStyle(.scroll)
    }
}
