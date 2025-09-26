import SwiftUI

/// An example of how you might make a custom page view style
struct CustomPageViewStyleExample: View {
    
    var body: some View {
        PageViewBasicExample()
            .pageViewStyle(MyCustomPageViewStyle())
    }
}

struct MyCustomPageViewStyle: PageViewStyle {
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            let current = configuration.selection.wrappedValue
            // Get the previous page's value, relative to the current
            if let previous = configuration.previous(current) {
                // Call the page's content view builder
                configuration.content(previous)
                    .scaleEffect(0.3)
                    .offset(x: -120)
            }
            // Repeat for the next page...
            if let next = configuration.next(current) {
                configuration.content(next)
                    .scaleEffect(0.3)
                    .offset(x: 120)
            }
            // ...and finally call the content for the current page
            configuration.content(current)
                .scaleEffect(0.6)
        }
    }
}

struct CustomPageViewStyleExample_Preview: PreviewProvider {
    
    static var previews: some View {
        CustomPageViewStyleExample()
    }
}
