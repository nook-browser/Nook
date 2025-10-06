#if canImport(UIKit)

import SwiftUI

extension PlatformPageView: UIViewControllerRepresentable {

    public typealias UIViewControllerType = UIPageViewController
    
    public func makeUIViewController(context: Context) -> UIPageViewController {
        let pageViewController = UIPageViewController(
            transitionStyle: configuration.transition.platform,
            navigationOrientation: configuration.orientation.platform,
            options: [.interPageSpacing: NSNumber(value: configuration.spacing)]
        )
        context.coordinator.contentBackground = context.environment.contentBackground
        pageViewController.delegate = context.coordinator
        pageViewController.dataSource = context.coordinator
        pageViewController.setViewControllers(
            [context.coordinator.makeViewController(selection)],
            direction: .forward,
            animated: context.transaction.animation != nil 
        )
        fixNavigationControllerContentScrollView(pageViewController)
        return pageViewController
    }
    
    public func updateUIViewController(
        _ pageViewController: UIPageViewController,
        context: Context
    ) {
        let isAnimated = context.transaction.animation != nil
        DispatchQueue.main.async {
            context.coordinator.go(
                to: selection,
                in: pageViewController,
                animated: isAnimated
            )
        }
        fixNavigationControllerContentScrollView(pageViewController)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}

// MARK: - Coordinator 

extension PlatformPageView {
    
    class Coordinator: NSObject, UIPageViewControllerDelegate, UIPageViewControllerDataSource {
        
        let parent: PlatformPageView
        var contentBackground: Visibility = .automatic
        
        init(_ parent: PlatformPageView) {
            self.parent = parent
        }
        
        // MARK: - Data Source
        
        public func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerBefore viewController: UIViewController
        ) -> UIViewController? {
            guard let viewController = viewController as? ContainerViewController else {
                return nil
            }
            if let previous = parent.previous(viewController.value) {
                return makeViewController(previous)
            } else {
                return nil
            }
        }
        
        public func pageViewController(
            _ pageViewController: UIPageViewController,
            viewControllerAfter viewController: UIViewController
        ) -> UIViewController? {
            guard let viewController = viewController as? ContainerViewController else {
                return nil
            }
            if let next = parent.next(viewController.value) {
                return makeViewController(next)
            } else {
                return nil
            }
        }
        
        // MARK: - Delegate
        
        public func pageViewController(
            _ pageViewController: UIPageViewController,
            didFinishAnimating finished: Bool,
            previousViewControllers: [UIViewController],
            transitionCompleted completed: Bool
        ) {
            guard completed else { return }
            parent.selection = selectedValue(in: pageViewController) ?? parent.selection
        }

        // MARK: - View Factory
        
        /// Creates a new container with hosting controller for a specified value.
        func makeViewController(_ value: SelectionValue) -> UIViewController {
            let viewController = ContainerViewController(
                value: value,
                view: parent.content(value),
                background: contentBackground
            )
            return viewController
        }
        
        // MARK: - Navigation
        
        /// Navigates the page controller to a specified value.
        func go(
            to value: SelectionValue,
            in pageViewController: UIPageViewController,
            animated: Bool = true
        ) {
            guard let currentViewController = pageViewController.viewControllers?.first as? ContainerViewController else {
                return
            }
            guard currentViewController.value != value else {
                return
            }
            pageViewController.setViewControllers(
                [makeViewController(value)],
                direction: .forward,
                animated: animated
            )
        }
        
        /// Returns the currently selected value as represented by the currently visible view controller.
        func selectedValue(in pageViewController: UIPageViewController) -> SelectionValue? {
            guard let container = pageViewController.viewControllers?.first as? ContainerViewController else {
                return nil
            }
            return container.value
        }
    }
}

// MARK: - Content view controller

extension PlatformPageView {
    
    class ContainerViewController: UIViewController {
        
        let value: SelectionValue
        let content: Content
        var hostingController: UIViewController?
        let background: Visibility
        
        init(
            value: SelectionValue,
            view: Content,
            background: Visibility
        ) {
            self.value = value
            self.content = view
            self.background = background
            super.init(nibName: nil, bundle: nil)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        // We only want to add the hosting controller once it's actually visible,
        // otherwise things like ScrollViews and PreferenceKeys go haywire.
        override func viewWillAppear(_ animated: Bool) {
            if self.hostingController == nil {
                let hostingController = ContentHostingController(rootView: content)
                hostingController.view.autoresizingMask = [
                    .flexibleWidth,
                    .flexibleHeight
                ]
                if background == .hidden {
                    hostingController.view.backgroundColor = .clear
                }
                self.addChild(hostingController)
                self.view.addSubview(hostingController.view)
                self.hostingController = hostingController
            }
            super.viewWillAppear(animated)
        }
        
        override func viewWillLayoutSubviews() {
            self.hostingController?.view.frame = self.view.frame
            super.viewWillLayoutSubviews()
        }
        
        override func viewDidDisappear(_ animated: Bool) {
            if let hostingController {
                hostingController.view.removeFromSuperview()
                hostingController.removeFromParent()
                self.hostingController = nil
            }
            super.viewDidDisappear(animated)
        }
    }
    
    class ContentHostingController: UIHostingController<Content> {
        
        // Stop SwiftUI interfering with parent toolbar / navigation titles
        override var navigationController: UINavigationController? {
            return nil
        }
    }
}

// MARK: - SwiftUI fixes

extension PlatformPageView {
    
    /// Corrects the content scroll view.
    ///
    /// The view hierarchy is too complex for the system to select the correct scrollview, breaking things
    /// like navigation bars and toolbars.
    ///
    /// It relies on SwiftUI internals which could change (specifically the navigation controller's hosting view).
    func fixNavigationControllerContentScrollView(_ pageViewController: UIPageViewController) {
        DispatchQueue.main.async {
            // Grab root view controller
            let viewController = pageViewController.viewControllers?.first
            // Do we have a navigation controller to fix?
            guard viewController?.navigationController != nil else {
                return
            }
            // If we do, are we in a hosting container?
            guard let hostingViewController = viewController?.parent?.parent else {
                return
            }
            // Can we find a scroll view?
            guard let scrollView = viewController?.view.firstSubview(of: UIScrollView.self) else {
                return
            }
            // Voila
            hostingViewController.setContentScrollView(scrollView)
        }
    }
}

// MARK: - Helpers

extension SwiftUI.Axis {
    
    var platform: UIPageViewController.NavigationOrientation {
        switch self {
        case .horizontal:
            return .horizontal
        case .vertical:
            return .vertical
        }
    }
}

extension PlatformPageViewConfiguration.Transition {
    
    /// Maps to a native page controller transition.
    var platform: UIPageViewController.TransitionStyle {
        switch self {
        case .book:
            return .pageCurl
        case .scroll:
            return .scroll
        default:
            return .scroll
        }
    }
}

extension UIView {
    
    func firstSubview<T: UIView>(of type: T.Type) -> T? {
        if let match = self as? T {
            return match
        }
        for subview in subviews {
            if let match = subview.firstSubview(of: type) {
                return match
            }
        }
        return nil
    }
}

#endif
