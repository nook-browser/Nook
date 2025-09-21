//
//  SimpleSpacePager.swift
//  Nook
//
//  Minimal AppKit wrapper that only handles space switching - everything else is SwiftUI
//

import SwiftUI
import AppKit


/// A custom hosting controller that can update its content when the width changes
private class UpdatableHostingController: NSHostingController<SpaceContentView> {
    private let space: Space
    private var currentWidth: CGFloat
    private weak var browserManager: BrowserManager?
    private weak var windowState: BrowserWindowState?
    private weak var splitManager: SplitViewManager?
    
    init(space: Space, width: CGFloat, browserManager: BrowserManager?, windowState: BrowserWindowState?, splitManager: SplitViewManager?) {
        self.space = space
        self.currentWidth = width
        self.browserManager = browserManager
        self.windowState = windowState
        self.splitManager = splitManager
        
        super.init(rootView: SpaceContentView(
            space: space,
            width: width,
            browserManager: browserManager,
            windowState: windowState,
            splitManager: splitManager
        ))
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateWidth(_ newWidth: CGFloat) {
        guard newWidth != currentWidth else { return }
        let oldWidth = currentWidth
        currentWidth = newWidth
        
        // Update the root view with the new width and inject environment objects
        rootView = SpaceContentView(
            space: space,
            width: newWidth,
            browserManager: browserManager,
            windowState: windowState,
            splitManager: splitManager
        )
        
        // Width updated successfully
    }
}

struct SimpleSpacePager: View {
    @Binding var selection: Int
    let spaces: [Space]
    let width: CGFloat
    let onSpaceChanged: (Int) -> Void
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void

    // Environment objects to pass through
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @EnvironmentObject var splitManager: SplitViewManager

    var body: some View {
        SimplePagerRepresentable(
            selection: $selection,
            spaces: spaces,
            width: width,
            onSpaceChanged: onSpaceChanged,
            onDragStarted: onDragStarted,
            onDragEnded: onDragEnded,
            browserManager: browserManager,
            windowState: windowState,
            splitManager: splitManager
        )
    }
}

private struct SimplePagerRepresentable: NSViewControllerRepresentable {
    @Binding var selection: Int
    let spaces: [Space]
    let width: CGFloat
    let onSpaceChanged: (Int) -> Void
    let onDragStarted: () -> Void
    let onDragEnded: () -> Void

    // Environment objects
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let splitManager: SplitViewManager

    func makeNSViewController(context: Context) -> SimplePagerController {
        let controller = SimplePagerController()
        controller.spaces = spaces
        controller.currentSelection = selection
        controller.currentWidth = width
        controller.onSpaceChanged = onSpaceChanged
        controller.onDragStarted = onDragStarted
        controller.onDragEnded = onDragEnded
        controller.browserManager = browserManager
        controller.windowState = windowState
        controller.splitManager = splitManager
        return controller
    }

    func updateNSViewController(_ controller: SimplePagerController, context: Context) {
        controller.spaces = spaces
        controller.currentSelection = selection
        controller.browserManager = browserManager
        controller.windowState = windowState
        controller.splitManager = splitManager
        
        // Update the pages when spaces change
        controller.updatePages()
        
        // Update the width of existing hosting controllers
        controller.updateWidth(width)
    }
}

private class SimplePagerController: NSPageController, NSPageControllerDelegate {
    var spaces: [Space] = []
    var currentSelection: Int = 0
    var currentWidth: CGFloat = 400.0
    
    // Environment objects
    weak var browserManager: BrowserManager?
    weak var windowState: BrowserWindowState?
    weak var splitManager: SplitViewManager?
    
    // Callbacks
    var onSpaceChanged: ((Int) -> Void)?
    var onDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?
    
    // Track hosting controllers for width updates
    private var hostingControllers: [String: UpdatableHostingController] = [:]

    // CRITICAL: Prevent duplicate NSPageController calls during gesture transitions
    private var isProcessingSpaceChange: Bool = false

    // CRITICAL: Time-based throttling to prevent rapid successive calls
    private var lastSpaceChangeTime: Date = Date.distantPast
    private let spaceChangeThrottleInterval: TimeInterval = 0.5 // 500ms throttle

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        transitionStyle = .horizontalStrip
        
        // Set up the page controller
        updatePages()
    }
    
    override func viewDidLayout() {
        super.viewDidLayout()
        
        // Lock paging to the left edge during resize by ensuring the current page
        // stays positioned at the left edge of the container
        let currentSize = self.view.bounds.size
        
        // Force the current page to be positioned at the left edge
        // This prevents the paging from moving around during sidebar resize
        if let currentPageView = self.selectedViewController?.view {
            currentPageView.frame = CGRect(x: 0, y: 0, width: currentSize.width, height: currentSize.height)
        }
        
        // Complete any pending transitions to ensure smooth resizing
        self.completeTransition()
    }
    
    func updatePages() {
        guard !spaces.isEmpty else { 
            return 
        }
        
        // Create simple identifiers for each space
        let identifiers = spaces.map { $0.id.uuidString }
        arrangedObjects = identifiers
        
        // Set the current selection
        if currentSelection >= 0 && currentSelection < spaces.count {
            selectedIndex = currentSelection
        }
    }
    
    func updateWidth(_ newWidth: CGFloat) {
        guard newWidth != currentWidth else { return }
        currentWidth = newWidth
        
        // Update all existing hosting controllers with the new width
        for (identifier, hostingController) in hostingControllers {
            hostingController.updateWidth(newWidth)
        }
        
        // Force the current page to refresh by temporarily changing and restoring the selection
        let currentIndex = selectedIndex
        if currentIndex >= 0 && currentIndex < spaces.count {
            // Force a refresh of the current page while maintaining left-edge positioning
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.selectedIndex = currentIndex
                
                // Ensure the current page stays locked to the left edge after width change
                if let currentPageView = self.selectedViewController?.view {
                    let currentSize = self.view.bounds.size
                    currentPageView.frame = CGRect(x: 0, y: 0, width: currentSize.width, height: currentSize.height)
                }
            }
        }
        
        // Width update completed
    }
    
    // MARK: - NSPageControllerDelegate
    
    func pageController(_ pageController: NSPageController, identifierFor object: Any) -> NSPageController.ObjectIdentifier {
        return object as? String ?? ""
    }
    
    func pageController(_ pageController: NSPageController, viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier) -> NSViewController {
        // Find the space for this identifier
        guard let spaceId = UUID(uuidString: identifier),
              let space = spaces.first(where: { $0.id == spaceId }) else {
            return NSViewController()
        }
        
        // Create a custom hosting controller that can update its content
        let hostingController = UpdatableHostingController(
            space: space,
            width: currentWidth,
            browserManager: browserManager,
            windowState: windowState,
            splitManager: splitManager
        )
        
        // Store the hosting controller for width updates
        hostingControllers[identifier] = hostingController
        
        return hostingController
    }
    
    func pageController(_ pageController: NSPageController, didTransitionTo object: Any) {
        // CRITICAL: Add surgical debugging to understand why this fires twice
        let callId = UUID().uuidString.prefix(8)
        print("🎯 [SimpleSpacePager] pageController didTransitionTo: \(callId)")

        // Find the index of the current space
        guard let identifier = object as? String,
              let spaceId = UUID(uuidString: identifier),
              let index = spaces.firstIndex(where: { $0.id == spaceId }) else {
            print("🎯 [SimpleSpacePager] Could not find space for identifier: \(object)")
            return
        }

        print("🎯 [SimpleSpacePager] Transitioning to space: \(spaces[index].name) (index: \(index), currentSelection: \(currentSelection))")

        // CRITICAL: Time-based throttling - reject calls that are too close together
        let now = Date()
        if now.timeIntervalSince(lastSpaceChangeTime) < spaceChangeThrottleInterval {
            print("🎯 [SimpleSpacePager] Throttling space change - too soon after last change (last: \(lastSpaceChangeTime), now: \(now))")
            return
        }

        // CRITICAL: More robust guard against duplicate calls from NSPageController
        // NSPageController can fire this method multiple times for the same gesture
        guard index != currentSelection else {
            print("🎯 [SimpleSpacePager] Already at this index, ignoring duplicate call")
            return
        }

        // CRITICAL: Add additional safety check - if we're already processing a space change, ignore this
        guard !isProcessingSpaceChange else {
            print("🎯 [SimpleSpacePager] Already processing space change, ignoring duplicate call")
            return
        }

        lastSpaceChangeTime = now

        currentSelection = index
        isProcessingSpaceChange = true

        // CRITICAL: Use MainActor.run to ensure proper thread safety and prevent race conditions
        Task { @MainActor [weak self] in
            guard let self = self else {
                print("🎯 [SimpleSpacePager] Self is nil, cannot complete space change")
                return
            }

            defer {
                self.isProcessingSpaceChange = false
                print("🎯 [SimpleSpacePager] Finished processing space change")
            }

            print("🎯 [SimpleSpacePager] Calling onSpaceChanged for index: \(index)")
            self.onSpaceChanged?(index)
        }
    }
}

// Pure SwiftUI content view - no AppKit complexity
private struct SpaceContentView: View {
    let space: Space
    let width: CGFloat
    
    // Environment objects
    let browserManager: BrowserManager?
    let windowState: BrowserWindowState?
    let splitManager: SplitViewManager?
    
    var body: some View {
        let isActive = windowState?.currentSpaceId == space.id
        let tabCount = browserManager?.tabManager.tabs(in: space).count ?? 0
        
        return SpaceView(
            space: space,
            isActive: isActive,
            width: width,
            onActivateTab: { browserManager?.selectTab($0, in: windowState!) },
            onCloseTab: { browserManager?.tabManager.removeTab($0.id) },
            onPinTab: { browserManager?.tabManager.pinTab($0) },
            onMoveTabUp: { browserManager?.tabManager.moveTabUp($0.id) },
            onMoveTabDown: { browserManager?.tabManager.moveTabDown($0.id) },
            onMuteTab: { $0.toggleMute() }
        )
        .environmentObject(browserManager!)  // ← Add this
        .environmentObject(windowState!)     // ← Add this  
        .environmentObject(splitManager!)    // ← Add this
        .frame(width: width)
    }
}
