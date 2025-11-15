import SwiftUI
import Highlightr

struct BoostCodeView: NSViewRepresentable {
    @Binding var code: String
    var language: String = "javascript"
    var theme: String = "xcode"
    
    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = CodeAttributedString()
        textStorage.language = language
        textStorage.highlightr.setTheme(to: theme)
        textStorage.highlightr.theme.setCodeFont(.monospacedSystemFont(ofSize: 12, weight: .medium))
        
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        textContainer.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.addTextContainer(textContainer)
        
        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.delegate = context.coordinator
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        
        let lineNumberView = LineNumberRulerView(textView: textView)
        
        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.verticalRulerView = lineNumberView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        
        textStorage.beginEditing()
        textStorage.setAttributedString(NSAttributedString(string: code))
        textStorage.endEditing()
        
        context.coordinator.textStorage = textStorage
        context.coordinator.lineNumberView = lineNumberView
        
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              let textStorage = context.coordinator.textStorage else { return }
        
        if textView.string != code {
            let selectedRange = textView.selectedRange()
            textStorage.beginEditing()
            textStorage.setAttributedString(NSAttributedString(string: code))
            textStorage.endEditing()
            textView.setSelectedRange(selectedRange)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: BoostCodeView
        var textStorage: CodeAttributedString?
        var lineNumberView: LineNumberRulerView?
        
        init(_ parent: BoostCodeView) {
            self.parent = parent
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.code = textView.string
            lineNumberView?.needsDisplay = true
        }
    }
}

class LineNumberRulerView: NSRulerView {
    weak var textView: NSTextView?
    
    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 60
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(textDidChange),
            name: NSText.didChangeNotification,
            object: textView
        )
    }
    
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc func textDidChange(_ notification: Notification) {
        needsDisplay = true
    }
    
    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let context = NSGraphicsContext.current?.cgContext else { return }
        
        context.setFillColor(NSColor.white.cgColor)
        context.fill(bounds)
        
        let relativePoint = self.convert(NSPoint.zero, from: textView)
        let layoutManager = textView.layoutManager!
        let textContainer = textView.textContainer!
        let text = textView.string
        
        var lineNumber = 1
        var index = 0
        
        while index < text.count {
            let lineRange = (text as NSString).lineRange(for: NSRange(location: index, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            
            let yPosition = relativePoint.y + rect.minY + textView.textContainerInset.height
            
            if yPosition >= self.bounds.minY && yPosition <= self.bounds.maxY {
                let lineString = "\(lineNumber)" as NSString
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                    .foregroundColor: NSColor.black
                ]
                
                let size = lineString.size(withAttributes: attributes)
                let point = NSPoint(x: (self.bounds.width - size.width) / 2, y: yPosition)
                lineString.draw(at: point, withAttributes: attributes)
            }
            
            index = NSMaxRange(lineRange)
            lineNumber += 1
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

struct CodeView: View {
    @State private var code = """
    function greet(name) {
        console.log(`Hello, ${name}!`);
    }
    
    greet("World");
    """
    
    var body: some View {
        VStack {
            BoostCodeView(code: $code, language: "javascript", theme: "xcode")
                .font(.system(size: 12, weight: .medium))
                .background(Color.white)
        }
    }
}

#Preview {
    CodeView()
}
