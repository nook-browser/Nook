import CoreGraphics

enum EssentialsGridLayout {
    static let minButtonWidth: CGFloat = 50
    static let itemSpacing: CGFloat = 8
    static let lineSpacing: CGFloat = 6
    static let maxColumns: Int = 3
    static let tileHeight: CGFloat = 52

    static func columnCount(for width: CGFloat, itemCount: Int) -> Int {
        guard width > 0 else { return 1 }
        let effectiveItems = max(1, itemCount)
        var cols = min(maxColumns, effectiveItems)
        while cols > 1 {
            let needed = CGFloat(cols) * minButtonWidth + CGFloat(cols - 1) * itemSpacing
            if needed <= width { break }
            cols -= 1
        }
        return max(1, cols)
    }
}
