// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
import Testing
@testable import NookTabsCore

struct OrderKeyTests {
    @Test func betweenOpenEnds() {
        let k = OrderKey.between(nil, nil)!
        #expect(k.rawValue == "V")
        #expect(OrderKey.between(nil, k)! < k)
        #expect(OrderKey.between(k, nil)! > k)
    }

    @Test func betweenAdjacentDigits() {
        let a = OrderKey("1"), b = OrderKey("2")
        let m = OrderKey.between(a, b)!
        #expect(a < m && m < b)
    }

    @Test func betweenPrefixKeys() {
        let a = OrderKey("1"), b = OrderKey("105")
        let m = OrderKey.between(a, b)!
        #expect(a < m && m < b)
        #expect(m.rawValue.last != "0")
    }

    @Test func rejectsInvalidInput() {
        #expect(OrderKey.between(OrderKey("5"), OrderKey("5")) == nil)
        #expect(OrderKey.between(OrderKey("6"), OrderKey("5")) == nil)
        #expect(OrderKey.between(OrderKey("50"), nil) == nil)
        #expect(OrderKey.between(OrderKey("5!"), nil) == nil)
    }

    @Test func repeatedInsertsStayOrdered() {
        var front = OrderKey.between(nil, nil)!
        var back = front
        let anchor = OrderKey("1")
        var afterAnchor = OrderKey("2")
        for _ in 0..<10_000 {
            let f = OrderKey.between(nil, front)!
            #expect(f < front)
            front = f

            let bk = OrderKey.between(back, nil)!
            #expect(bk > back)
            back = bk

            // Insert directly after the same sibling every time.
            let mid = OrderKey.between(anchor, afterAnchor)!
            #expect(anchor < mid && mid < afterAnchor)
            afterAnchor = mid
        }
        #expect(afterAnchor.rawValue.count < 3_000)
        #expect(front.rawValue.count < 3_000 && back.rawValue.count < 3_000)
    }

    @Test func sequenceIsIncreasing() {
        let keys = OrderKey.sequence(count: 200)
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == 200)
    }
}
