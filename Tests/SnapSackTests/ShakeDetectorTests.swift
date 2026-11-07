import CoreGraphics
import Foundation
import XCTest
@testable import SnapSack

final class ShakeDetectorTests: XCTestCase {
    /// Sweeps the pointer left and right `strokes` times, `distance` points each way, at 60 Hz.
    /// Returns whether a shake was recognised at any point.
    private func shakes(_ sensitivity: ShakeSensitivity, strokes: Int, distance: CGFloat) -> Bool {
        var detector = ShakeDetector(at: .zero, sensitivity: sensitivity)
        var time: TimeInterval = 0
        var x: CGFloat = 0
        var detected = false
        let steps = Int(distance / 10)
        for stroke in 0..<strokes {
            let target: CGFloat = stroke % 2 == 0 ? distance : 0
            let step = (target - x) / CGFloat(steps)
            for _ in 0..<steps {
                x += step
                time += 1.0 / 60
                if detector.feed(CGPoint(x: x, y: 0), at: time) { detected = true }
            }
        }
        return detected
    }

    func testHighNeedsThreeTurns() {
        XCTAssertTrue(shakes(.high, strokes: 4, distance: 60))
        XCTAssertFalse(shakes(.high, strokes: 3, distance: 60))
    }

    func testMediumNeedsFourTurns() {
        XCTAssertFalse(shakes(.medium, strokes: 4, distance: 60))
        XCTAssertTrue(shakes(.medium, strokes: 5, distance: 60))
    }

    func testLowNeedsFiveTurnsOfLongStrokes() {
        XCTAssertFalse(shakes(.low, strokes: 5, distance: 90))
        XCTAssertTrue(shakes(.low, strokes: 6, distance: 90))
    }

    func testLowIgnoresStrokesShorterThanItsMinimum() {
        XCTAssertFalse(shakes(.low, strokes: 8, distance: 60))
    }
}
