import AppKit
import QuartzCore

/// Every tunable in one place.
enum Tune {
    // Card
    static let cardArea: CGFloat = 5_760                       // every thumbnail covers about this much area
    static let aspectRange: ClosedRange<CGFloat> = 0.8...1.6   // wider/taller shots are cropped to fit
    static let cornerRadius: CGFloat = 7
    static let maxCards = 8                                    // a ninth replaces the oldest

    // Hanging off the cursor
    static let pivotInset = CGPoint(x: 10, y: 14)              // distance of the pin from the cursor tip
    static let edgeMargin: CGFloat = 10
    static let followRate: CGFloat = 34                        // easing toward the cursor (per second)
    static let trailFalloff: CGFloat = 0.75                    // each card back eases this much slower: a small delay
    static let minFollowRate: CGFloat = 24                     // floor, so the back cards never drift far behind
    static let stackStep = CGPoint(x: 4, y: 4)                 // fixed offset per depth: the accordion's spacing
    static let stackLean: CGFloat = 0.01                       // radians of fan-out per card back, tiny

    // Tilt and settle
    static let angleStiffness: CGFloat = 420
    static let angleDamping: CGFloat = 40                      // critically damped: settles without ringing
    static let swingPerPointPerSecond: CGFloat = 0.000055      // radians of tilt per pt/s of cursor speed
    static let maxSwing: CGFloat = 0.066                       // about 4 degrees, at most
    static let scaleStiffness: CGFloat = 420
    static let scaleDamping: CGFloat = 34
    static let startScale: CGFloat = 0.85

    // Fan
    static let fanScale: CGFloat = 1.9                         // cards grow so you can tell them apart
    static let fanHoverScale: CGFloat = 1.07
    static let fanCurvature: CGFloat = 0.0005                  // how much the ends of the fan droop
    static let closeBadgeSize: CGFloat = 12                    // the × badge, in card units
    static let closeHitRadius: CGFloat = 16                    // clicks this close to the badge's centre count, in points
    static let fanHoverMargin: CGFloat = 26                    // the hovered card stays active this far outside its edge

    // Leaving
    static let flightDuration: CFTimeInterval = 0.23
}

/// One screenshot in your hand: its window plus the physics state that drives it.
@MainActor
final class Card {
    let panel: CarryPanel
    let png: Data
    let size: CGSize
    let born: CFTimeInterval

    var pos: CGPoint            // the pin, in global screen coordinates
    var anchor: CGPoint         // where on the card the pin is: (0,1) = top-left, (0.5,0.5) = centre
    var angle: CGFloat = 0
    var angleVel: CGFloat = 0
    var scale: CGFloat = Tune.startScale
    var scaleVel: CGFloat = 0
    var alpha: CGFloat = 0
    var lift: CGFloat = 0       // hover lift while fanned

    /// Whether the × is showing: only the active card in the fan.
    var closeShown = false {
        didSet {
            if closeShown != oldValue { panel.setCloseShown(closeShown) }
        }
    }

    init(image: NSImage, png: Data, pos: CGPoint, anchor: CGPoint, now: CFTimeInterval) {
        let fitted = Card.fitSize(for: image)
        self.size = fitted
        self.panel = CarryPanel(image: image, size: fitted)
        self.png = png
        self.pos = pos
        self.anchor = anchor
        self.born = now
    }

    /// A consistent, small card: same area every time, the shape follows the screenshot.
    static func fitSize(for image: NSImage) -> CGSize {
        let raw = image.size.width / max(image.size.height, 1)
        let aspect = min(max(raw, Tune.aspectRange.lowerBound), Tune.aspectRange.upperBound)
        return CGSize(
            width: (Tune.cardArea * aspect).squareRoot().rounded(),
            height: (Tune.cardArea / aspect).squareRoot().rounded()
        )
    }

    /// Where the middle of the card currently is, whatever it's pinned by.
    var center: CGPoint {
        CGPoint(
            x: pos.x + (0.5 - anchor.x) * size.width * scale,
            y: pos.y + (0.5 - anchor.y) * size.height * scale
        )
    }

    /// Changes which point of the card is the pin without moving the card on screen.
    func reanchor(to newAnchor: CGPoint) {
        let middle = center
        anchor = newAnchor
        pos = CGPoint(
            x: middle.x - (0.5 - newAnchor.x) * size.width * scale,
            y: middle.y - (0.5 - newAnchor.y) * size.height * scale
        )
    }

    func render(alphaMultiplier: CGFloat) {
        panel.render(pivot: pos, anchor: anchor, angle: angle, scale: scale, alpha: alpha * alphaMultiplier)
    }
}
