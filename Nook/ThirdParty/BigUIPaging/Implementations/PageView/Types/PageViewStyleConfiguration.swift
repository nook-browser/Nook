import SwiftUI

/// The properties of a page view instance.
///
/// A configuration represents the properties of a page view, such as the current selection and next item.
/// You use a configuration as part of a ``PageViewStyle``.
public struct PageViewStyleConfiguration {
    
    /// A type erased value
    public struct Value: Hashable {
            
        let wrappedValue: any Hashable
        
        init(_ wrappedValue: any Hashable) {
            self.wrappedValue = wrappedValue
        }
        
        public static func == (lhs: PageViewStyleConfiguration.Value, rhs: PageViewStyleConfiguration.Value) -> Bool {
            lhs.wrappedValue.hashValue == rhs.wrappedValue.hashValue
        }
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(wrappedValue)
        }
    }
    
    /// A type erased page
    public struct Page: View {
        
        let wrappedView: AnyView
        
        init<V>(_ view: V) where V: View {
            self.wrappedView = AnyView(view)
        }
        
        public var body: some View {
            wrappedView
        }
    }

    /// The current selection
    public var selection: Binding<Value>
    
    /// The next item relative to the given value
    public let next: (Value) -> Value?
    
    /// The previous item relative to the given value
    public let previous: (Value) -> Value?
    
    /// A page view for the given value
    public let content: (Value) -> Page
}

extension PageViewStyleConfiguration {
    
    /// Returns the values surrounding a given value.
    ///
    /// This is a convenience method that can be utilised for lazy loading values. It calls the next and previous
    /// closure on either side of the value  until the limit is reached. The results are combined, including the initial value.
    ///
    /// Returned is also the position of the initial value in the returned array.
    ///
    public func values(surrounding value: Value, limit: Int = 3) -> ([Value], Int) {
        var currentValue = value
        var previousValues = [Value]()
        while let previousValue = previous(currentValue), previousValues.count < limit {
            previousValues.insert(previousValue, at: 0)
            currentValue = previousValue
        }
        currentValue = value
        var nextValues = [value]
        while let nextValue = next(currentValue), nextValues.count <= limit {
            nextValues.append(nextValue)
            currentValue = nextValue
        }
        let allValues = previousValues + nextValues
        let selectedIndex = previousValues.count
        return (allValues, selectedIndex)
    }
}
