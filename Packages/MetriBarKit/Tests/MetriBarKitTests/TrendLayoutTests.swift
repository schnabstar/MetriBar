import Testing

@testable import MetriBarKit

struct TrendLayoutTests {
    private func points(_ segments: [[TrendPoint]]) -> [[[Double]]] {
        segments.map { $0.map { [$0.x, $0.y] } }
    }

    @Test func oneLineWithoutGaps() {
        let segments = TrendLayout.segments([0, 50, 100], range: 0...100)
        #expect(points(segments) == [[[0, 0], [0.5, 0.5], [1, 1]]])
    }

    @Test func aGapBreaksTheLineAndKeepsThePlaces() {
        let segments = TrendLayout.segments([10, 20, nil, nil, 30, 40], range: 0...100)
        #expect(segments.count == 2)
        #expect(segments[0].map(\.x) == [0, 0.2])
        // The samples after the gap are drawn at their own places, not next to the first ones.
        #expect(segments[1].map(\.x) == [0.8, 1])
    }

    @Test func aSampleAloneIsARunOfOnePoint() {
        let segments = TrendLayout.segments([10, nil, 30, nil, 50], range: 0...100)
        #expect(segments.map(\.count) == [1, 1, 1])
    }

    @Test func leadingAndTrailingGapsLeaveRoom() {
        let segments = TrendLayout.segments([nil, nil, 10, 20, nil], range: 0...100)
        #expect(segments.count == 1)
        #expect(segments[0].map(\.x) == [0.5, 0.75])
    }

    @Test func noValuesNoLines() {
        #expect(TrendLayout.segments([]).isEmpty)
        #expect(TrendLayout.segments([nil, nil, nil]).isEmpty)
    }

    @Test func fitsTheRangeToTheValuesWhenNoneIsGiven() {
        let segments = TrendLayout.segments([5, 10, 15])
        #expect(segments[0].map(\.y) == [0, 0.5, 1])
    }

    @Test func aFlatLineRunsThroughTheMiddle() {
        #expect(TrendLayout.segments([7, 7, 7])[0].map(\.y) == [0.5, 0.5, 0.5])
        #expect(TrendLayout.segments([3], range: nil)[0].map(\.y) == [0.5])
    }

    @Test func valuesOutsideTheRangeAreClamped() {
        let segments = TrendLayout.segments([-10, 50, 130], range: 0...100)
        #expect(segments[0].map(\.y) == [0, 0.5, 1])
    }

    @Test func aGapDoesNotInfluenceTheAutomaticRange() {
        let segments = TrendLayout.segments([10, nil, 20])
        #expect(segments.flatMap { $0.map(\.y) } == [0, 1])
    }
}
