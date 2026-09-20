import Foundation
import Testing
@testable import EyesUpApp

@Suite @MainActor struct SparklineTests {
    @Test func shortSeriesAreDrawnAsTheyAre() {
        let values = (0..<10).map(Double.init)
        #expect(Sparkline.drawable(values) == values)
    }

    @Test func longSeriesAreThinnedButKeepTheirShape() {
        let values = (0..<300).map(Double.init)
        let drawn = Sparkline.drawable(values)
        #expect(drawn.count == Sparkline.maxPoints)
        #expect(drawn.first == 0)
        #expect(drawn.last == 299)          // the newest sample is never dropped
        #expect(drawn == drawn.sorted())    // evenly spread, still in order
    }
}
