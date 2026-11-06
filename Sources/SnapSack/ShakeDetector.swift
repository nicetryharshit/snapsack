import CoreGraphics
import Foundation

/// Recognises a shake: several quick direction reversals, each with real travel, inside a short window.
/// Works per axis so a horizontal, vertical or diagonal shake all count. A small hysteresis stops
/// ordinary hand tremor from registering as a reversal.
struct ShakeDetector {
    private struct Axis {
        var direction = 0            // +1, -1, or 0 until the pointer first moves
        var extreme: CGFloat         // furthest point reached in the current direction
        var segmentStart: CGFloat    // where the current stroke began
        var reversals: [TimeInterval] = []
    }

    private var x: Axis
    private var y: Axis

    var minTravel: CGFloat = 55          // a stroke must cover at least this much to count
    var hysteresis: CGFloat = 8          // ...and you must come back this far to turn it around
    var window: TimeInterval = 0.65      // all reversals must land inside this many seconds
    var reversalsNeeded = 4

    init(at point: CGPoint) {
        x = Axis(extreme: point.x, segmentStart: point.x)
        y = Axis(extreme: point.y, segmentStart: point.y)
    }

    /// Feed the latest pointer position. Returns true once a shake has been recognised.
    mutating func feed(_ point: CGPoint, at time: TimeInterval) -> Bool {
        let travel = minTravel, slack = hysteresis, span = window
        Self.advance(&x, to: point.x, at: time, minTravel: travel, hysteresis: slack, window: span)
        Self.advance(&y, to: point.y, at: time, minTravel: travel, hysteresis: slack, window: span)
        return x.reversals.count >= reversalsNeeded || y.reversals.count >= reversalsNeeded
    }

    private static func advance(
        _ axis: inout Axis,
        to p: CGFloat,
        at t: TimeInterval,
        minTravel: CGFloat,
        hysteresis: CGFloat,
        window: TimeInterval
    ) {
        switch axis.direction {
        case 0:
            if abs(p - axis.extreme) >= hysteresis {
                axis.direction = p > axis.extreme ? 1 : -1
                axis.segmentStart = axis.extreme
                axis.extreme = p
            }
        case 1:
            if p > axis.extreme {
                axis.extreme = p
            } else if axis.extreme - p >= hysteresis {
                if axis.extreme - axis.segmentStart >= minTravel { axis.reversals.append(t) }
                axis.direction = -1
                axis.segmentStart = axis.extreme
                axis.extreme = p
            }
        default:
            if p < axis.extreme {
                axis.extreme = p
            } else if p - axis.extreme >= hysteresis {
                if axis.segmentStart - axis.extreme >= minTravel { axis.reversals.append(t) }
                axis.direction = 1
                axis.segmentStart = axis.extreme
                axis.extreme = p
            }
        }
        axis.reversals.removeAll { t - $0 > window }
    }
}
