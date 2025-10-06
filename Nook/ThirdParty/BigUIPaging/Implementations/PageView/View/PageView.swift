import SwiftUI

/// A container view that manages navigation between related views.
///
/// Pages can be navigated programmatically by updating the selection binding to a specified value
/// or directly by the user with a gesture or action.
///
/// ## Creating a PageView
///
/// There are two ways to initialise a PageView. The simplest is with a ForEach data source:
///
/// ```swift
/// @State private var selection: Int = 1
///
/// var body: some View {
///     PageView(selection: $selection) {
///         ForEach(1...10, id: \.self) { id in
///             Text("Page \(value)")
///         }
///     }
///     .pageViewStyle(.scroll)
/// }
/// ```
///
/// Alternatively you can you can use the next and previous closure to return a value relative to another value:
///
/// ```swift
/// @State private var selection: Int = 1
///
/// var body: some View {
///     PageView(selection: $selection) { value in
///         value + 1
///     } previous: { value in
///         value > 1 ? value - 1 : nil
///     } content: { value in
///         Text("Page \(value)")
///     }
/// }
/// ```
///
/// ## Styles and Transitions
///
/// The exact navigation gesture or transition depends on the chosen style. The default
/// style is ``PlainPageViewStyle`` that has no transitions or gestures.
///
/// You set a style by using the ``SwiftUI/View/pageViewStyle(_:)`` modifier:
///
/// ```swift
/// PageView(selection: $selection) {
///     ...
/// }
/// .pageViewStyle(.bookStack)
///   ```
///
/// You can create your own custom transitions and interactions by adopting ``PageViewStyle``.
///
/// ## Page Orientation
///
/// Styles that support support vertical and horizontal navigation (scroll and book) can be configured with the
/// orientation view modifier:
///
/// ```swift
/// .pageViewOrientation(.vertical)
/// ```
/// Controls such as ``PageViewNavigationButton`` also respond to this modifier adapting the chevron
/// direction as appropriate.
///
/// ## Navigation
///
/// In addition to controlling the current page with the selection binding, you can also use the
/// environment's ``PageViewNavigateAction`` action to navigate the page view backwards and forwards.
///
/// ```swift 
/// @Environment(\.navigatePageView) private var navigate
/// @Environment(\.canNavigatePageView) private var canNavigate
///
/// var body: some View {
///     Button {
///         navigate(.forwards)
///     } label: {
///         Text("Next")
///     }
///     .disabled(!canNavigate.contains(.forwards))
/// }
/// ```
///
/// Included is also ``PageViewNavigationButton`` which provides standardised forwards and
/// backwards controls:
///
/// ```swift
/// PageView {
///     ...
/// }
/// .toolbar {
///     ToolbarItem {
///         PageViewNavigationButton()
///             .pageViewOrientation(.vertical)
///     }
/// }
/// .pageViewEnvironment()
/// ```
///
public struct PageView<SelectionValue, Page>: View where SelectionValue: Hashable, Page: View {
    
    @Binding var selection: SelectionValue
    let next: (SelectionValue) -> SelectionValue?
    let previous: (SelectionValue) -> SelectionValue?
    @ViewBuilder let pageContent: (SelectionValue) -> Page
    @State private var id = UUID()
    @StateObject private var values: ValueStore
    
    /// Creates a new page view that computes its pages using closures to determine the next and previous
    /// page value.
    /// - Parameters:
    ///   - selection: A binding to a selected value.
    ///   - next: A closure that returns the next value from the provided value.
    ///   - previous: A closure that returns the previous value from the provided value.
    ///   - content: A view builder that returns the page content for a given value.
    public init(
        selection: Binding<SelectionValue>,
        next: @escaping (SelectionValue) -> SelectionValue?,
        previous: @escaping (SelectionValue) -> SelectionValue?,
        @ViewBuilder content: @escaping (SelectionValue) -> Page
    ) {
        self._selection = selection
        self.next = next
        self.previous = previous
        self.pageContent = content
        self._values = StateObject(wrappedValue: ValueStore(next, previous))
    }
    
    @Environment(\.pageViewStyle) private var style
    
    public var body: some View {
        AnyView(style.makeConcreteView(configuration))
            .environment(\.navigatePageView, configuration.navigateAction(id))
            .preference(
                key: PageViewCanNavigatePreference.self,
                value: configuration.canNavigate
            )
            .preference(
                key: PageViewNavigateActionPreference.self,
                value: configuration.navigateAction(id)
            )
    }
}

// MARK: - Convenience initialisers

extension PageView {

    /// Creates a new page view that computes its pages on demand from an underlying collection of
    /// hashable data.
    /// - Parameters:
    ///   - selection: A binding to a selected value.
    ///   - content: A `ForEach` containing some hashable data.
    public init<Data>(
        selection: Binding<SelectionValue>,
        content: () -> ForEach<Data, Data.Element, Page>
    ) where Data : RandomAccessCollection, SelectionValue == Data.Element {
        let content = content()
        let data = content.data
        let page = content.content
        self.init(selection: selection) { value in
            guard let index = data.firstIndex(of: value) else {
                return nil
            }
            guard index != data.endIndex else {
                return nil
            }
            let next = data.index(after: index)
            guard data.indices.contains(next) else {
                return nil
            }
            return data[next]
        } previous: { value in
            guard let index = data.firstIndex(of: value) else {
                return nil
            }
            guard index != data.startIndex else {
                return nil
            }
            let previous = data.index(before: index)
            guard data.indices.contains(previous) else {
                return nil
            }
            return data[previous]
        } content: { value in
            page(value)
        }
    }
    
    /// Creates a new page view that computes its pages on demand from an underlying collection of
    /// identifiable data.
    /// - Parameters:
    ///   - selection: A binding to a selected value.
    ///   - content: A `ForEach` containing some identifiable data.
    public init<Data>(
        selection: Binding<SelectionValue>,
        content: () -> ForEach<Data, Data.Element.ID, Page>
    ) where Data : RandomAccessCollection, Data.Element : Identifiable, SelectionValue == Data.Element.ID {
        let content = content()
        let data = content.data
        let page = content.content
        self.init(selection: selection) { id in
            guard let index = data.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            let next = data.index(after: index)
            guard data.indices.contains(next) else {
                return nil
            }
            return data[next].id
        } previous: { id in
            guard let index = data.firstIndex(where: { $0.id == id }) else {
                return nil
            }
            let prev = data.index(before: index)
            guard data.indices.contains(prev) else {
                return nil
            }
            return data[prev].id
        } content: { id in
            let value = data.first(where: { $0.id == id }) ?? data[data.startIndex]
            page(value)
        }
    }
}

// MARK: - Style Handling

extension PageView {
    
    var configuration: PageViewStyleConfiguration {
        .init(selection: configurationSelection) { value in
            values[value, 1]
        } previous: { value in
            values[value, -1]
        } content: { value in
            .init(pageContent(value.wrappedValue as! SelectionValue))
        }
    }
    
    var configurationSelection: Binding<PageViewStyleConfiguration.Value> {
        .init {
            .init(selection)
        } set: { newValue in
            self.selection = newValue.wrappedValue as! SelectionValue
        }
    }
}

struct ConcretePageViewStyle<Style>: View where Style: PageViewStyle {
    
    let configuration: PageViewStyleConfiguration
    let style: Style
    
    var body: some View {
        style.makeBody(configuration: configuration)
    }
}

extension PageViewStyle {
    
    func makeConcreteView(_ configuration: Configuration) -> some View {
        ConcretePageViewStyle(configuration: configuration, style: self)
    }
}

// MARK: - Navigation

extension PageViewStyleConfiguration {
    
    func navigateAction(_ id: UUID) -> PageViewNavigateAction {
        .init(id: id) { direction in
            switch direction {
            case .forwards:
                if let next = next(selection.wrappedValue) {
                    self.selection.wrappedValue = next
                }
            case .backwards:
                if let previous = previous(selection.wrappedValue) {
                    self.selection.wrappedValue = previous
                }
            default:
                break 
            }
        }
    }
    
    var canNavigate: PageViewDirection {
        var directions = PageViewDirection()
        if next(selection.wrappedValue) != nil {
            directions.insert(.forwards)
        }
        if previous(selection.wrappedValue) != nil {
            directions.insert(.backwards)
        }
        return directions
    }
}

// MARK: - Caching 

extension PageView {
    
    /// A cache for next and previous values.
    @MainActor class ValueStore: ObservableObject {
        
        typealias Value = PageViewStyleConfiguration.Value
        
        struct Key: Hashable {
            let value: SelectionValue
            let offset: Int
        }
        
        var cache = [Key: SelectionValue?]()
        let next: (SelectionValue) -> SelectionValue?
        let previous: (SelectionValue) -> SelectionValue?
        
        init(
            _ next: @escaping (SelectionValue) -> SelectionValue?,
            _ previous: @escaping (SelectionValue) -> SelectionValue?
        ) {
            self.next = next
            self.previous = previous
        }
        
        subscript(value: SelectionValue, offset: Int) -> SelectionValue? {
            get {
                let key = Key(value: value, offset: offset)
                if let cached = cache[key] {
                    return cached
                }
                let closure = offset == 1 ? next : previous
                let nextValue = closure(value)
                cache[key] = nextValue
                return nextValue
            }
        }
        
        subscript(value: Value, offset: Int) -> Value? {
            get {
                guard let value = value.wrappedValue as? SelectionValue else {
                    return nil
                }
                guard let nextValue = self[value, offset] else {
                    return nil
                }
                return .init(nextValue)
            }
        }
    }
}


struct PageView_Previews: PreviewProvider {
    
    static var previews: some View {
        PageViewBasicExample()
    }
}
