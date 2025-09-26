import SwiftUI

/// # "We always long for the forbidden things, and desire what is denied us"*
///
/// Since there's no public API for inspecting SwiftUI structs, we need to use Mirror.
/// No one wants to poke around, but without this our components can't nicely interpolate with system ones.
/// I just want to know the `String` value of a `Label`. I'm not asking for the world here.
/// Why does Tim Apple get to have all the fun? We can be trusted!
///
extension View {
    
    typealias Action = () -> Void
    
    /// Recursively searches the view hierarchy and returns the first `String` value.
    ///
    /// - Note: If your string contains any interpolation (e.g. an inline value), this will return the raw format.
    func _firstString() -> String? {
        _firstValue(of: String.self)
    }
    
    /// Recursively searches the view hierarchy and returns the first `Image` value.
    func _firstImage() -> Image? {
        _firstValue(of: Image.self)
    }
    
    /// Recursively searches the view hierarchy and returns the first `() -> Void` value.
    func _firstAction() -> Action? {
        _firstValue(of: Action.self)
    }
    
    func _firstLabelIcon() -> AnyView? {
        guard let icon = _firstValue(labelled: "icon") as? any View else {
            return nil
        }
        return AnyView(icon)
    }
    
    /// Return all the views in a `TupleView`.
    ///
    /// If view isn't a tuple, an empty array is returned.
    func _children() -> [any View] {
        let mirror = Mirror(reflecting: self)
        guard let value = mirror.descendant("value") else {
            return []
        }
        let tuple = Mirror(reflecting: value)
        return tuple.children.compactMap { $0.value as? any View }
    }

    /// Recursively searches the view hierarchy and returns the first matching type.
    func _firstValue<T>(of type: T.Type) -> T? {
        return _firstValue(of: type, in: Mirror(reflecting: self).children)
    }
    
    func _firstValue<T>(of type: T.Type, in children: Mirror.Children) -> T? {
        for child in children {
            let mirror = Mirror(reflecting: child.value)
            if mirror.subjectType == type.self {
                return child.value as? T
            }
            if let match = _firstValue(of: type, in: mirror.children) {
                return match
            }
        }
        return nil
    }
    
    func _firstValue(labelled label: String, children: Mirror.Children? = nil) -> Any? {
        let children = children ?? Mirror(reflecting: self).children
        for child in children {
            let mirror = Mirror(reflecting: child.value)
            if child.label == label {
                return child.value
            }
            if let match = _firstValue(labelled: label, children: mirror.children) {
                return match
            }
        }
        return nil
    }
    
    func _printHierarchy(children: Mirror.Children? = nil, level: Int = 0) {
        let children = children ?? Mirror(reflecting: self).children
        for child in children {
            let mirror = Mirror(reflecting: child.value)
            let indent = (0...level).map { _ in "-" }.joined()
            print("\(indent)| \(child.label!)")
            print("\(indent)|   \(child.value)")
            _printHierarchy(children: mirror.children, level: level + 1)
        }
    }
}

extension Image {
    
    func _systemName() -> String? {
        guard let provider = _firstValue(labelled: "base") else {
            return nil
        }
        let mirror = Mirror(reflecting: provider)
        guard let location = mirror.children.first(where: { $0.label == "location" }) else {
            return nil
        }
        guard String(describing: location.value) == "system" else {
            return nil
        }
        let name = mirror.children.first(where: { $0.label == "name" })
        return name?.value as? String
    }
}

#if canImport(UIKit)
extension Image {
    
    func _systemImage() -> UIImage? {
        if let symbol = _systemName() {
            return UIImage(systemName: symbol)
        } else {
            return nil
        }
    }
}
#endif
