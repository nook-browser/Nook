import SwiftUI

/// An example of how to go from a Grid to a PageView, and back again.
struct ExampleGridToPageView: View {
    
    @State private var isOpen = false
    @State private var selection = 1
    @State private var openedSelection: Int? = nil
    @State private var dismissProgress: Double = 0.0
    @Namespace private var transition
    
    let columns: [GridItem] = [
        .init(.adaptive(minimum: 120, maximum: 200), spacing: 15)
    ]
    
    var body: some View {
        ScrollViewReader { scrollView in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 15) {
                    ForEach(1...100, id: \.self) { id in
                        // The card can't be in two places at once, otherwise the
                        // geometry effect has a meltdown.
                        if id == selection && isOpen {
                            // Placeholder for our card
                            Color.clear
                        } else {
                            ExampleCardPage(value: id)
                                // Keep the selected card on top
                                .zIndex(id == selection ? 100 : 0.0)
                                .matchedGeometryEffect(
                                    id: id,
                                    in: transition
                                )
                                .aspectRatio(1.0, contentMode: .fit)
                                .onTapGesture {
                                    // Keep track of which card we opened with so
                                    // we know if user has swiped in PageView.
                                    // This is useful so we can scroll the grid
                                    // to keep the card visible once they dismiss.
                                    openedSelection = id
                                    selection = id
                                    isOpen = true
                                }
                        }
                    }
                }
                .scenePadding()
            }
            // ...keep scroll view in sync with the PageView
            .onChange(of: selection) { _ in
                if isOpen == true && openedSelection != selection {
                    scrollView.scrollTo(selection, anchor: .center)
                }
            }
        }
        .overlay {
            Rectangle()
                .fill(.background)
                .ignoresSafeArea()
                .opacity(isOpen ? 1.0 - (dismissProgress / 2) : 0.0)
                .animation(.easeInOut(duration: 0.2), value: isOpen)
        }
        .overlay {
            if isOpen {
                PageView(selection: $selection) {
                    ForEach(1...100, id: \.self) { id in
                        ExampleCardPage(value: id)
                    }
                }
                .pageViewStyle(.scroll)
                .pageViewSpacing(15)
                .cardMask()
                .matchedGeometryEffect(
                    id: selection,
                    in: transition
                )
                .aspectRatio(0.7, contentMode: .fit)
                .dragToDismiss($isOpen, progress: $dismissProgress)
                // We need a transition to prevent the opacity transition.
                // Scale works, but for whatever reason 1.0 gives us a flash.
                .transition(.scale(scale: 0.99))
                .onTapGesture {
                    isOpen = false
                }
            }
        }
//        .animation(.easeInOut(duration: 2), value: isOpen)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isOpen)
        #if os(macOS)
        .frame(minWidth: 300, minHeight: 300)
        #endif
    }
}

// MARK: - Drag to Dismiss

extension View {
    
    func dragToDismiss(
        _ isOpen: Binding<Bool>,
        progress: Binding<Double>,
        threshold: Double = 150
    ) -> some View {
        modifier(
            DragToDismissModifier(
                isOpen: isOpen,
                progress: progress,
                threshold: threshold
            )
        )
    }
}

struct DragToDismissModifier: ViewModifier {
    
    @Binding var isOpen: Bool
    @Binding var progress: Double
    let threshold: Double
    @State private var offset = 0.0
    
    func body(content: Content) -> some View {
        content
            .offset(y: offset)
            .gesture(gesture)
    }
    
    // This is a bit iffy, onEnded doesn't get called sometimes.
    // Might wanna use GestureState instead.
    var gesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = value.translation.height
                progress = max(0.0, min(1.0, offset / threshold))
            }
            .onEnded { value in
                if value.translation.height > threshold {
                    isOpen = false
                    progress = 0.0
                } else {
                    withAnimation(.bouncy) {
                        offset = 0.0
                        progress = 0.0
                    }
                }
            }
    }
}

// MARK: - Demo Pages

struct ExampleCardPage: View {
    
    let value: Int
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .center) {
                Rectangle()
                    .fill(value.color)
                Image(systemName: "\(value).circle.fill")
                    .font(.system(size: geometry.size.height / 4))
                    .foregroundStyle(.white)
            }
        }
        .cardMask()
        .ignoresSafeArea()
    }
}

extension View {
    
    func cardMask() -> some View {
        mask(RoundedRectangle(cornerRadius: 25.0, style: .continuous))
    }
}


// MARK: - Preview

struct ExampleGridToPageView_Previews: PreviewProvider {
    
    static var previews: some View {
        ZStack {
            ExampleGridToPageView()
        }
    }
}
