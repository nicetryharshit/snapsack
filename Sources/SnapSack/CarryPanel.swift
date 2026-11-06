import AppKit
import QuartzCore

/// The window for one card: a borderless, click-through panel above everything (including full-screen apps)
/// that just draws a thumbnail where it's told to. All motion lives in `Hand`; this only renders.
@MainActor
final class CarryPanel: NSPanel {
    private let reach: CGFloat                       // the panel is a (2 * reach) square centred on the pin
    private let cardLayer = CALayer()
    private let contentLayer = CALayer()
    private let closeLayer = CAShapeLayer()          // the × on the active card in the fan

    init(image: NSImage, size: CGSize) {
        // Big enough for a corner-pinned card with its tilt, and for a centre-pinned card fanned out at full size.
        let reachValue = (hypot(size.width, size.height) * 1.15 + 40).rounded()
        reach = reachValue

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: reachValue * 2, height: reachValue * 2),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        alphaValue = 0

        // Layer-hosting content view: we own the layer tree, y axis points up.
        let host = NSView(frame: NSRect(x: 0, y: 0, width: reachValue * 2, height: reachValue * 2))
        host.layer = CALayer()
        host.wantsLayer = true
        contentView = host

        let radius = Tune.cornerRadius
        let mouse = NSEvent.mouseLocation
        let backing = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2

        cardLayer.bounds = CGRect(origin: .zero, size: size)
        cardLayer.shadowColor = NSColor.black.cgColor
        cardLayer.shadowOpacity = 0.26
        cardLayer.shadowRadius = 9
        cardLayer.shadowOffset = CGSize(width: 0, height: -4)
        cardLayer.shadowPath = CGPath(
            roundedRect: cardLayer.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil
        )

        contentLayer.frame = cardLayer.bounds
        contentLayer.cornerRadius = radius
        contentLayer.masksToBounds = true
        contentLayer.contentsGravity = .resizeAspectFill
        contentLayer.contentsScale = backing
        contentLayer.minificationFilter = .trilinear
        contentLayer.magnificationFilter = .linear
        contentLayer.borderWidth = 1
        contentLayer.borderColor = NSColor(white: 1, alpha: 0.55).cgColor
        contentLayer.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)

        cardLayer.addSublayer(contentLayer)

        // The ×: a small dark disc at the top-right corner, hidden until the card is active in the fan.
        let badge = Tune.closeBadgeSize
        closeLayer.bounds = CGRect(x: 0, y: 0, width: badge, height: badge)
        closeLayer.position = CGPoint(x: size.width - 1, y: size.height - 1)
        // A red disc with a darker rim and a white ×, like a delete badge. Sizes are in card units, so they
        // scale with the card in the fan.
        closeLayer.path = CGPath(ellipseIn: closeLayer.bounds.insetBy(dx: 0.4, dy: 0.4), transform: nil)
        closeLayer.fillColor = NSColor(calibratedRed: 0.93, green: 0.27, blue: 0.25, alpha: 1).cgColor
        closeLayer.strokeColor = NSColor(calibratedRed: 0.62, green: 0.12, blue: 0.11, alpha: 0.6).cgColor
        closeLayer.lineWidth = 0.6
        closeLayer.shadowColor = NSColor.black.cgColor
        closeLayer.shadowOpacity = 0.3
        closeLayer.shadowRadius = 1.2
        closeLayer.shadowOffset = CGSize(width: 0, height: -0.6)
        closeLayer.opacity = 0

        let cross = CAShapeLayer()
        cross.frame = closeLayer.bounds
        let r = badge * 0.2
        let c = CGPoint(x: badge / 2, y: badge / 2)
        let strokes = CGMutablePath()
        strokes.move(to: CGPoint(x: c.x - r, y: c.y - r))
        strokes.addLine(to: CGPoint(x: c.x + r, y: c.y + r))
        strokes.move(to: CGPoint(x: c.x - r, y: c.y + r))
        strokes.addLine(to: CGPoint(x: c.x + r, y: c.y - r))
        cross.path = strokes
        cross.strokeColor = NSColor.white.cgColor
        cross.fillColor = nil
        cross.lineWidth = 1.1
        cross.lineCap = .round
        cross.lineCap = .round
        closeLayer.addSublayer(cross)
        cardLayer.addSublayer(closeLayer)

        host.layer?.addSublayer(cardLayer)
    }

    /// Shows or hides the × with a short fade.
    func setCloseShown(_ shown: Bool) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        closeLayer.opacity = shown ? 1 : 0
        CATransaction.commit()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Don't let AppKit push the window back below the menu bar: cards have to follow the cursor
    /// everywhere, including the very top of the screen.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    func render(pivot: CGPoint, anchor: CGPoint, angle: CGFloat, scale: CGFloat, alpha: CGFloat) {
        setFrameOrigin(NSPoint(x: pivot.x - reach, y: pivot.y - reach))
        alphaValue = alpha

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cardLayer.anchorPoint = anchor
        cardLayer.position = CGPoint(x: reach, y: reach)
        var transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        transform = CATransform3DScale(transform, scale, scale, 1)
        cardLayer.transform = transform
        CATransaction.commit()
    }
}
