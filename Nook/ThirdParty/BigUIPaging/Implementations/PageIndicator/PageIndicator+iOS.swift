#if canImport(UIKit)

import SwiftUI

struct PlatformPageIndicator: UIViewRepresentable {
    
    typealias UIViewType = UIPageControl

    /// The currently selected page index.
    @Binding var selection: Int
    
    /// The total number of pages.
    let total: Int
    
    /// Whether the page indicator timer in resumed or paused.
    @Binding var isProgressing: Bool
    
    /// Indicator icons. Page index represented by key. Tuple value represents selected and unselected states respectively.
    let icons: [Int: (Image?, Image?)]

    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.numberOfPages = total
        
        let coordinator = context.coordinator
        control.addTarget(coordinator,
            action: #selector(coordinator.selectionChanged),
            for: .valueChanged
        )

        if #available(iOS 17.0, *) {
            if let duration = context.environment.pageDuration {
                let progress = UIPageControlTimerProgress(preferredDuration: duration)
                progress.resetsToInitialPageAfterEnd = true
                control.progress = progress
            }
        }
        
        for entry in icons {
            let page = entry.key
            let (selected, unselected) = entry.value
            if let selected = selected?._systemImage() {
                control.setCurrentPageIndicatorImage(selected, forPage: page)
            }
            if let unselected = unselected?._systemImage() {
                control.setIndicatorImage(unselected, forPage: page)
            }
        }
        
        return control
    }
    
    func updateUIView(_ control: UIPageControl, context: Context) {
        control.numberOfPages = total
        control.currentPage = selection
        control.isUserInteractionEnabled = context.environment.isEnabled
        control.allowsContinuousInteraction = context.environment.allowsContinuousInteraction
        control.backgroundStyle = context.environment.pageIndicatorBackgroundStyle.platform
        control.hidesForSinglePage = context.environment.singlePageVisibility == .hidden
        
        if let color = context.environment.pageIndicatorCurrentColor {
            control.currentPageIndicatorTintColor = UIColor(color)
        }
        
        if let color = context.environment.pageIndicatorColor {
            control.pageIndicatorTintColor = UIColor(color)
        }
        
        if #available(iOS 17.0, *) {
            if let timer = control.progress as? UIPageControlTimerProgress {
                if isProgressing && timer.isRunning == false {
                    timer.resumeTimer()
                } else if isProgressing == false && timer.isRunning == true {
                    timer.pauseTimer()
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
}

extension PlatformPageIndicator {
    
    public class Coordinator: NSObject {
        
        let parent: PlatformPageIndicator
        
        init(_ parent: PlatformPageIndicator) {
            self.parent = parent
        }
        
        @objc func selectionChanged(_ sender: UIPageControl) {
            self.parent.selection = sender.currentPage
        }
    }
}

extension PageIndicator.BackgroundStyle {
    
    var platform: UIPageControl.BackgroundStyle {
        switch self {
        case .automatic:
            return .automatic
        case .prominent:
            return .prominent
        case .minimal:
            return .minimal
        }
    }
}

struct PlatformPageIndicator_Previews: PreviewProvider {
    
    static var previews: some View {
        PageIndicatorExample()
    }
}

#endif
