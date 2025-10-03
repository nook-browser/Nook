#if canImport(AppKit)

import SwiftUI

extension PlatformPageView: NSViewControllerRepresentable {

    typealias NSViewControllerType = NSPageController
    
    func makeNSViewController(context: Context) -> NSPageController {
        let pageController = NSPageController()
        pageController.view = NSView()
        pageController.view.wantsLayer = true
        pageController.delegate = context.coordinator
        let (arrangedObjects, selectedIndex) = makeArrangedObjects(around: selection)
        pageController.arrangedObjects = arrangedObjects
        pageController.selectedIndex = selectedIndex
        pageController.transitionStyle = configuration.transition.platform
        return pageController
    }
    
    func updateNSViewController(
        _ pageController: NSPageController,
        context: Context
    ) {
        // Keep selection value in sync with page controller
        if context.coordinator.selectedValue(in: pageController) != selection {
            context.coordinator.go(
                to: selection,
                in: pageController,
                animated: context.transaction.animation != nil
            )
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    /// Returns the arranged objects around a given value.
    ///
    /// This method also returns the index of the value in the returned array, which can be used to set the
    /// selected index of the page controller.
    func makeArrangedObjects(around value: SelectionValue, limit: Int = 3) -> ([Any], Int) {
        var currentValue = value
        var previousObjects = [SelectionValue]()
        while let previousValue = previous(currentValue), previousObjects.count < limit {
            previousObjects.insert(previousValue, at: 0)
            currentValue = previousValue
        }
        currentValue = value
        var nextObjects = [value]
        while let nextValue = next(currentValue), nextObjects.count <= limit {
            nextObjects.append(nextValue)
            currentValue = nextValue
        }
        let allObjects = previousObjects + nextObjects
        let selectedIndex = previousObjects.count
        return (allObjects, selectedIndex)
    }
}

// MARK: - Coordinator

extension PlatformPageView {
    
    class Coordinator: NSObject, NSPageControllerDelegate {
        
        let parent: PlatformPageView
        var viewCache = [SelectionValue: NSView]()
        
        init(_ parent: PlatformPageView) {
            self.parent = parent
        }
        
        // MARK: - Delegate
        
        func pageController(
            _ pageController: NSPageController,
            identifierFor object: Any
        ) -> NSPageController.ObjectIdentifier {
            return .container
        }
        
        func pageController(
            _ pageController: NSPageController,
            viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier
        ) -> NSViewController {
            let viewController = PlatformPageView.ContainerViewController()
            viewController.coordinator = self
            return viewController
        }
        
        func pageController(
            _ pageController: NSPageController,
            prepare viewController: NSViewController, with object: Any?
        ) {
            guard let viewController = viewController as? PlatformPageView.ContainerViewController else {
                return
            }
            if let value = object as? SelectionValue {
                viewController.prepare(value)
            }
        }
        
        func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
            pageController.completeTransition()
            parent.selection = selectedValue(in: pageController) ?? parent.selection
        }
        
        func pageController(
            _ pageController: NSPageController,
            didTransitionTo object: Any
        ) {
            guard let value = object as? SelectionValue else {
                return
            }
            // If we have reached the end, request more arranged objects around
            // the currently selected value.
            let lastValue = pageController.arrangedObjects.last as? SelectionValue
            let firstValue = pageController.arrangedObjects.first as? SelectionValue
            if value == lastValue || value == firstValue {
                let (newObjects, selectedIndex) = parent.makeArrangedObjects(around: value)
                pageController.arrangedObjects = newObjects
                pageController.selectedIndex = selectedIndex
                flushViewCache(in: pageController)
            }
        }
        
        // MARK: - View Factory
        
        /// Returns a hosting view for the specified value.
        ///
        /// The view is cached until flushed, so repeated calls will return the same view instance.
        func makeView(for value: SelectionValue) -> NSView {
            if let cached = viewCache[value] {
                if let hostingView = cached as? PlatformPageView.HostingView {
                    hostingView.rootView = parent.content(value)
                }
                return cached
            }
            let view = PlatformPageView.HostingView(rootView: parent.content(value))
            viewCache[value] = view
            return view
        }
        
        /// Removes cached views that are no longer part of the controller's arranged objects.
        func flushViewCache(in pageController: NSPageController) {
            guard let currentValues = pageController.arrangedObjects as? [SelectionValue] else {
                return
            }
            for value in viewCache.keys {
                if currentValues.contains(value) == false {
                    viewCache.removeValue(forKey: value)
                }
            }
        }
        
        // MARK: - Navigation
        
        /// Returns the currently selected value as represented by the currently selected view controller.
        func selectedValue(in pageController: NSPageController) -> SelectionValue? {
            guard let container = pageController.selectedViewController as? PlatformPageView.ContainerViewController else {
                return nil
            }
            return container.representedValue
        }
        
        /// Navigates the page controller to the specified value.
        func go(
            to value: SelectionValue,
            in pageController: NSPageController,
            animated: Bool = false
        ) {
            let (arrangedObjects, selectedIndex) = parent.makeArrangedObjects(around: value)
            pageController.arrangedObjects = arrangedObjects
            if animated {
                NSAnimationContext.runAnimationGroup { _ in
                    pageController.animator().selectedIndex = selectedIndex
                } completionHandler: {
                    pageController.completeTransition()
                }
            } else {
                pageController.selectedIndex = selectedIndex
            }
        }
    }
}

// MARK: - Container

extension PlatformPageView {
    
    class ContainerViewController: NSViewController {
        
        weak var coordinator: Coordinator?
                
        init() {
            super.init(nibName: nil, bundle: nil)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func loadView() {
            self.view = NSView()
            self.view.autoresizingMask = [.width, .height]
        }
        
        var representedValue: SelectionValue? {
            representedObject as? SelectionValue
        }
        
        /// Updates the container view to present a hosting controller for the supplied value.
        func prepare(_ value: SelectionValue) {
            self.representedObject = value
            // Clean up old view...
            for subview in view.subviews {
                subview.removeFromSuperview()
            }
            // Prepare new view...
            guard let contentView = coordinator?.makeView(for: value) else {
                return
            }
            contentView.autoresizingMask = [.width, .height]
            contentView.frame = view.bounds
            contentView.removeFromSuperview()
            self.view.addSubview(contentView)
        }
    }
    
    class HostingView: NSHostingView<Content> {
        
        // Without this SwiftUI will swallow all scroll events, rendering
        // the page controller's swipe gesture useless.
        override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool {
            return true
        }
    }
}

extension NSPageController.ObjectIdentifier {
    static let container = "container"
}

extension PlatformPageViewConfiguration.Transition {
    
    /// Map to native page controller style.
    var platform: NSPageController.TransitionStyle {
        switch self {
        case .scroll:
            return .horizontalStrip
        case .historyStack:
            return .stackHistory
        case .bookStack:
            return .stackBook
        default:
            return .horizontalStrip
        }
    }
}

struct PlatformPageView_Mac_Previews: PreviewProvider {
    
    static var previews: some View {
        PageViewBasicExample()
            .pageViewStyle(.scroll)
    }
}

#endif
