import SwiftUI

/// An example of how to create a deck of cards.
@available(macOS, unavailable)
struct CardDeckExample: View {
    
    @State private var selection: Int = 1
    private let totalPages = 10
    
    var body: some View {
        VStack {
            PageView(selection: $selection) {
                ForEach(1...totalPages, id: \.self) { value in
                    ExamplePage(value: value)
                        // Resize to be more card-like.
                        .aspectRatio(0.7, contentMode: .fit)
                }
            }
            // Set the card style
            .pageViewStyle(.cardDeck)
            // Control how much of the card edges are visible
            .scaleEffect(0.9)
            // Card styling options
            .pageViewCardCornerRadius(45.0)
            .pageViewCardShadow(.visible)
            // A tap gesture works great here
            .onTapGesture {
                print("Tapped card \(selection)")
            }
            
            PageIndicator(
                selection: indicatorSelection,
                total: totalPages
            )
            .pageIndicatorColor(.secondary.opacity(0.3))
            .pageIndicatorCurrentColor(selection.color)
        }
    }
    
    // Here's where you'd map your selection to a page index.
    // In this example it's just the selection minus one.
    var indicatorSelection: Binding<Int> {
        .init {
            selection - 1
        } set: { newValue in
            selection = newValue + 1
        }
    }
}

// MARK: - Preview

@available(macOS, unavailable)
struct CardDeckExample_Previews: PreviewProvider {
    
    static var previews: some View {
        CardDeckExample()
    }
}
