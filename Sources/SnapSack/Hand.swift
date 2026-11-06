import AppKit
import QuartzCore

/// Everything you're holding.
///
/// Up to eight cards hang off the cursor as a little stack: the newest is on top and closest to the pointer, and
/// each one behind follows the one in front a touch more slowly, so the stack trails like a tail. On a double-click
/// with more than one card, the hand fans out around the click point and holds still so you can pick one.
@MainActor
final class Hand: NSObject {
    enum Mode { case carrying, fanned }

    /// Called when the hand is shaken: Carrier decides what that means.
    var onShake: (() -> Void)?

    private(set) var mode: Mode = .carrying
    var isFanned: Bool { mode == .fanned }
    var count: Int { cards.count }
    var isEmpty: Bool { cards.isEmpty }

    // MARK: State

    fileprivate enum Exit {
        case flying(from: CGPoint, to: CGPoint)
        case drifting
        case vanishing
    }

    @MainActor
    fileprivate final class Leaving {
        let card: Card
        let exit: Exit
        let start: CFTimeInterval
        let startScale: CGFloat
        var velocity: CGPoint
        var onLanded: (() -> Void)?

        init(card: Card, exit: Exit, start: CFTimeInterval, velocity: CGPoint, onLanded: (() -> Void)?) {
            self.card = card
            self.exit = exit
            self.start = start
            self.startScale = card.scale
            self.velocity = velocity
            self.onLanded = onLanded
        }
    }

    fileprivate struct FanSlot {
        var center: CGPoint
        var angle: CGFloat
    }

    private var cards: [Card] = []             // oldest first; the last one is on top, nearest the cursor
    private var leaving: [Leaving] = []        // cards still animating out
    private var slots: [FanSlot] = []
    private var hovered: Int?
    private var fanStart: CFTimeInterval = 0
    private var fanOrigin = CGPoint.zero

    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var lastMouse = CGPoint.zero
    private var velocity = CGPoint.zero
    private var shake = ShakeDetector(at: .zero)
    private var armShakeAt: CFTimeInterval = 0
    private var flipX = false
    private var flipY = false
    private var suspended = false

    // MARK: - Adding and removing

    func add(image: NSImage, png: Data) {
        guard mode == .carrying else { return }
        let now = CACurrentMediaTime()
        let mouse = NSEvent.mouseLocation

        if cards.count >= Tune.maxCards { leave(cards.removeFirst(), .vanishing) }

        if cards.isEmpty {
            lastMouse = mouse
            velocity = .zero
            flipX = false
            flipY = false
            shake = ShakeDetector(at: mouse)
        }
        armShakeAt = now + 0.5   // the end of the region-select drag must not read as a shake

        updateFlips(at: mouse, size: Card.fitSize(for: image), stacked: cards.count + 1)
        let anchor = CGPoint(x: flipX ? 1 : 0, y: flipY ? 0 : 1)
        let card = Card(
            image: image,
            png: png,
            pos: pivotPoint(for: mouse, anchor: anchor),
            anchor: anchor,
            now: now
        )
        cards.append(card)
        card.render(alphaMultiplier: 1)            // alpha is 0: park it in place before ordering it in, so it never flashes elsewhere
        card.panel.orderFrontRegardless()
        startLinkIfNeeded()
    }

    /// Esc: put the newest card away.
    func removeNewest() {
        guard mode == .carrying, let card = cards.popLast() else { return }
        leave(card, .vanishing)
    }

    /// Shake: let the whole hand go.
    func tossAll() {
        guard mode == .carrying else { return }
        let speed = hypot(velocity.x, velocity.y)
        let limit: CGFloat = 520
        let k = speed > limit ? limit / speed : 1
        let drift = CGPoint(x: velocity.x * k, y: velocity.y * k)
        for card in cards { leave(card, .drifting, velocity: drift) }
        cards.removeAll()
    }

    /// While the system crosshair is up the hand hides, so it can't end up in your screenshot.
    func suspend() { suspended = true }

    func resume() {
        suspended = false
        lastMouse = NSEvent.mouseLocation
        velocity = .zero
        shake = ShakeDetector(at: lastMouse)
        armShakeAt = CACurrentMediaTime() + 0.5
    }

    // MARK: - Dropping

    /// One card in hand: lift it off the cursor and float it to `landing`; `onLanded` fires on arrival.
    func flyNewest(to landing: CGPoint, onLanded: @escaping (Data) -> Void) {
        guard mode == .carrying, let card = cards.popLast() else { return }
        card.reanchor(to: CGPoint(x: 0.5, y: 0.5))
        let png = card.png
        leave(card, .flying(from: card.pos, to: landing), onLanded: { onLanded(png) })
    }

    /// Several cards: spread them around `origin` and hold them there.
    func openFan(at origin: CGPoint) {
        guard mode == .carrying, cards.count > 1 else { return }
        mode = .fanned
        hovered = nil
        fanStart = CACurrentMediaTime()
        fanOrigin = origin
        slots = layoutFan(around: origin)
        for card in cards { card.reanchor(to: CGPoint(x: 0.5, y: 0.5)) }
    }

    enum FanClick { case picked, removed, missed }

    /// A click while the fan is open. On the active card's × it removes that card; on a card it picks it, so it
    /// flies to `landing` and the rest return to the hand; on empty space everything goes back to the cursor.
    @discardableResult
    func fanClick(at mouse: CGPoint, landing: CGPoint, onLanded: @escaping (Data) -> Void) -> FanClick {
        guard mode == .fanned else { return .missed }
        // Inside a card counts as a pick. Outside it only counts when it's the × of the active card.
        let index: Int
        if let inside = hitTest(mouse) {
            index = inside
        } else if let near = hitTestSticky(mouse), isOnClose(near, mouse) {
            index = near
        } else {
            closeFan()
            return .missed
        }
        if isOnClose(index, mouse) {
            removeFanned(at: index)
            return .removed
        }
        let card = cards.remove(at: index)
        card.closeShown = false
        let png = card.png
        leave(card, .flying(from: card.pos, to: landing), onLanded: { onLanded(png) })
        mode = .carrying
        hovered = nil
        returnToHand()
        return .picked
    }

    /// Takes one card out of the fan without pasting it. The rest spread out again; with one card left the fan closes.
    private func removeFanned(at index: Int) {
        let card = cards.remove(at: index)
        card.closeShown = false
        leave(card, .vanishing)
        hovered = nil
        if cards.count < 2 {
            mode = .carrying
            returnToHand()
            return
        }
        slots = layoutFan(around: fanOrigin)
    }

    /// Whether `point` is on the × of card `index`. Only the × that's showing can be clicked.
    private func isOnClose(_ index: Int, _ point: CGPoint) -> Bool {
        let card = cards[index]
        guard card.closeShown else { return false }
        let c = card.center
        let dx = point.x - c.x
        let dy = point.y - c.y
        let cosA = cos(card.angle)
        let sinA = sin(card.angle)
        let x = dx * cosA + dy * sinA
        let y = -dx * sinA + dy * cosA
        // The badge sits one point in from the top-right corner of the card.
        let bx = (card.size.width / 2 - 1) * card.scale
        let by = (card.size.height / 2 - 1) * card.scale
        return hypot(x - bx, y - by) <= Tune.closeHitRadius
    }

    /// Everything back on the cursor.
    func closeFan() {
        guard mode == .fanned else { return }
        mode = .carrying
        hovered = nil
        returnToHand()
    }

    private func returnToHand() {
        let now = CACurrentMediaTime()
        lastMouse = NSEvent.mouseLocation
        velocity = .zero
        shake = ShakeDetector(at: lastMouse)
        armShakeAt = now + 0.4
        let anchor = CGPoint(x: flipX ? 1 : 0, y: flipY ? 0 : 1)
        for card in cards {
            card.lift = 0
            card.closeShown = false
            card.reanchor(to: anchor)
        }
    }

    private func leave(
        _ card: Card,
        _ exit: Exit,
        velocity: CGPoint = .zero,
        onLanded: (() -> Void)? = nil
    ) {
        leaving.append(Leaving(
            card: card,
            exit: exit,
            start: CACurrentMediaTime(),
            velocity: velocity,
            onLanded: onLanded
        ))
        startLinkIfNeeded()
    }

    // MARK: - Frame loop

    private func startLinkIfNeeded() {
        guard link == nil else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let link = screen.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTime = CACurrentMediaTime()
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = CGFloat(max(1.0 / 240.0, min(now - lastTime, 1.0 / 30.0)))
        lastTime = now
        let mouse = NSEvent.mouseLocation

        switch mode {
        case .carrying: stepHanging(dt: dt, now: now, mouse: mouse)
        case .fanned:   stepFanned(dt: dt, now: now, mouse: mouse)
        }
        stepLeaving(dt: dt, now: now)

        let visible: CGFloat = suspended ? 0 : 1
        for card in cards { card.render(alphaMultiplier: visible) }
        for item in leaving { item.card.render(alphaMultiplier: 1) }

        if cards.isEmpty && leaving.isEmpty { stopLink() }
    }

    /// The stack hanging off the cursor.
    private func stepHanging(dt: CGFloat, now: CFTimeInterval, mouse: CGPoint) {
        guard let top = cards.last else { return }

        // Smoothed pointer velocity.
        let raw = CGPoint(x: (mouse.x - lastMouse.x) / dt, y: (mouse.y - lastMouse.y) / dt)
        let blend = 1 - exp(-dt * 22)
        velocity.x += (raw.x - velocity.x) * blend
        velocity.y += (raw.y - velocity.y) * blend
        lastMouse = mouse

        // Which side of the cursor the stack hangs on; slides smoothly when it flips near an edge.
        updateFlips(at: mouse, size: top.size, stacked: cards.count)
        let slide = 1 - exp(-dt * 16)
        let targetAnchor = CGPoint(x: flipX ? 1 : 0, y: flipY ? 0 : 1)
        let behind = CGPoint(
            x: flipX ? -Tune.stackStep.x : Tune.stackStep.x,
            y: flipY ? Tune.stackStep.y : -Tune.stackStep.y
        )

        // A few degrees of lean, following horizontal speed.
        let lean = clamp(-velocity.x * Tune.swingPerPointPerSecond, -Tune.maxSwing, Tune.maxSwing)

        for (depth, card) in cards.reversed().enumerated() {           // depth 0 is the top card
            card.anchor.x += (targetAnchor.x - card.anchor.x) * slide
            card.anchor.y += (targetAnchor.y - card.anchor.y) * slide

            // Every card is pinned to the cursor with a fixed offset per depth, so the stack stays tight:
            // the tail can't grow longer than `depth * stackStep`, however fast you move.
            let pinned = pivotPoint(for: mouse, anchor: card.anchor)
            let desired = CGPoint(
                x: pinned.x + behind.x * CGFloat(depth),
                y: pinned.y + behind.y * CGFloat(depth)
            )
            // Cards further back ease a little more slowly, which is the delay you see as they catch up.
            let rate = max(Tune.minFollowRate, Tune.followRate * pow(Tune.trailFalloff, CGFloat(depth)))
            let ease = 1 - exp(-dt * rate)
            card.pos.x += (desired.x - card.pos.x) * ease
            card.pos.y += (desired.y - card.pos.y) * ease

            // Cards behind lean a hair apart, like a held hand.
            let spread = (depth % 2 == 0 ? -1 : 1) * Tune.stackLean * CGFloat(depth)
            spring(&card.angle, &card.angleVel, to: lean + spread,
                   k: Tune.angleStiffness, c: Tune.angleDamping, dt: dt)
            spring(&card.scale, &card.scaleVel, to: 1,
                   k: Tune.scaleStiffness, c: Tune.scaleDamping, dt: dt)
            card.alpha = min(1, CGFloat((now - card.born) / 0.10))
        }

        if now > armShakeAt, shake.feed(mouse, at: now) { onShake?() }
    }

    /// The fan: every card eases to its slot and holds; the one under the pointer lifts.
    private func stepFanned(dt: CGFloat, now: CFTimeInterval, mouse: CGPoint) {
        hovered = hitTestSticky(mouse)
        let ease = 1 - exp(-dt * 18)
        for (index, card) in cards.enumerated() where index < slots.count {
            card.alpha = 1
            guard now - fanStart >= Double(index) * 0.018 else { continue }   // a slight cascade
            let slot = slots[index]
            let isHovered = hovered == index
            card.closeShown = isHovered
            card.lift += ((isHovered ? 14 : 0) - card.lift) * ease
            card.pos.x += (slot.center.x - card.pos.x) * ease
            card.pos.y += (slot.center.y + card.lift - card.pos.y) * ease
            spring(&card.angle, &card.angleVel, to: slot.angle,
                   k: Tune.angleStiffness, c: Tune.angleDamping, dt: dt)
            spring(&card.scale, &card.scaleVel,
                   to: Tune.fanScale * (isHovered ? Tune.fanHoverScale : 1),
                   k: Tune.scaleStiffness, c: Tune.scaleDamping, dt: dt)
        }
    }

    private func stepLeaving(dt: CGFloat, now: CFTimeInterval) {
        var finished: [Leaving] = []
        for item in leaving {
            let card = item.card
            let t = CGFloat(now - item.start)

            switch item.exit {
            case .flying(let from, let to):
                let p = min(1, t / CGFloat(Tune.flightDuration))
                let move = easeInOut(p)
                card.pos = CGPoint(x: from.x + (to.x - from.x) * move, y: from.y + (to.y - from.y) * move)
                let lift = sin(min(1, p / 0.3) * .pi)                         // a brief rise as it lets go
                card.scale = item.startScale + (0.55 - item.startScale) * move + 0.06 * lift
                let fade = min(1, max(0, (p - 0.6) / 0.4))
                card.alpha = 1 - fade * fade * (3 - 2 * fade)
                spring(&card.angle, &card.angleVel, to: 0, k: Tune.angleStiffness, c: Tune.angleDamping, dt: dt)
                if p >= 1 {
                    item.onLanded?()
                    item.onLanded = nil
                    finished.append(item)
                }

            case .drifting:
                let p = min(1, t / 0.24)
                let eased = 1 - pow(1 - p, 3)
                let drag = exp(-dt * 9)
                item.velocity.x *= drag
                item.velocity.y *= drag
                card.pos.x += item.velocity.x * dt
                card.pos.y += item.velocity.y * dt
                spring(&card.angle, &card.angleVel, to: 0, k: Tune.angleStiffness, c: Tune.angleDamping, dt: dt)
                card.scale = item.startScale * (1 - 0.12 * eased)
                card.alpha = 1 - eased
                if p >= 1 { finished.append(item) }

            case .vanishing:
                let p = min(1, t / 0.16)
                let eased = 1 - pow(1 - p, 3)
                spring(&card.angle, &card.angleVel, to: 0, k: Tune.angleStiffness, c: Tune.angleDamping, dt: dt)
                card.scale = item.startScale * (1 - 0.10 * eased)
                card.alpha = 1 - eased
                if p >= 1 { finished.append(item) }
            }
        }

        for item in finished {
            item.card.panel.orderOut(nil)
            leaving.removeAll { $0 === item }
        }
    }

    // MARK: - Geometry

    private func pivotPoint(for mouse: CGPoint, anchor: CGPoint) -> CGPoint {
        CGPoint(
            x: mouse.x + lerp(Tune.pivotInset.x, -Tune.pivotInset.x, anchor.x),
            y: mouse.y + lerp(Tune.pivotInset.y, -Tune.pivotInset.y, anchor.y)
        )
    }

    /// Decides whether the stack should hang left/up of the cursor so it never runs off the screen.
    /// The "come back" threshold is looser than the "flip" one, so it can't flicker at the boundary.
    private func updateFlips(at mouse: CGPoint, size: CGSize, stacked: Int) {
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let depth = CGFloat(max(stacked - 1, 0))
        let width = size.width + Tune.stackStep.x * depth
        let height = size.height + Tune.stackStep.y * depth
        let inset = Tune.pivotInset
        let margin = Tune.edgeMargin

        let overRight = mouse.x + inset.x + width + margin > area.maxX
        let overRightLoose = mouse.x + inset.x + width + margin + 70 > area.maxX
        if !flipX, overRight { flipX = true } else if flipX, !overRightLoose { flipX = false }

        let overBottom = mouse.y - inset.y - height - margin < area.minY
        let overBottomLoose = mouse.y - inset.y - height - margin - 70 < area.minY
        if !flipY, overBottom { flipY = true } else if flipY, !overBottomLoose { flipY = false }
    }

    /// An arc of cards above the click point (below it if there isn't room), held in the air, oldest at the left.
    private func layoutFan(around origin: CGPoint) -> [FanSlot] {
        let n = cards.count
        let screen = NSScreen.screens.first { NSMouseInRect(origin, $0.frame, false) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let cardW = (cards.map { $0.size.width }.max() ?? 80) * Tune.fanScale
        let cardH = (cards.map { $0.size.height }.max() ?? 80) * Tune.fanScale

        var spacing = cardW * 0.85
        spacing = min(spacing, (area.width - 80 - cardW) / CGFloat(max(n - 1, 1)))
        let totalWidth = spacing * CGFloat(n - 1) + cardW
        let centerX = min(
            max(origin.x, area.minX + totalWidth / 2 + 16),
            max(area.maxX - totalWidth / 2 - 16, area.minX + totalWidth / 2 + 16)
        )

        var baseY = origin.y + 56 + cardH / 2
        if baseY + cardH / 2 + 16 > area.maxY { baseY = origin.y - 56 - cardH / 2 }
        baseY = max(baseY, area.minY + cardH / 2 + 16)

        let mid = CGFloat(n - 1) / 2
        return (0..<n).map { i in
            let x = (CGFloat(i) - mid) * spacing
            let y = -Tune.fanCurvature * x * x
            let angle = -atan(2 * Tune.fanCurvature * x)
            return FanSlot(center: CGPoint(x: centerX + x, y: baseY + y), angle: angle)
        }
    }

    /// The topmost card under `point`, accounting for each card's tilt and size.
    private func hitTest(_ point: CGPoint) -> Int? {
        for index in cards.indices.reversed() where contains(index, point, margin: 0) {
            return index
        }
        return nil
    }

    /// The card under `point`, or else the card that was already hovered if the pointer is just outside it. This
    /// lets the pointer travel off the edge toward the × (which sits in the corner) without losing the card.
    private func hitTestSticky(_ point: CGPoint) -> Int? {
        if let index = hitTest(point) { return index }
        if let hovered, hovered < cards.count, contains(hovered, point, margin: Tune.fanHoverMargin) {
            return hovered
        }
        return nil
    }

    private func contains(_ index: Int, _ point: CGPoint, margin: CGFloat) -> Bool {
        let card = cards[index]
        let c = card.center
        let dx = point.x - c.x
        let dy = point.y - c.y
        let cosA = cos(card.angle)
        let sinA = sin(card.angle)
        let x = dx * cosA + dy * sinA
        let y = -dx * sinA + dy * cosA
        return abs(x) <= card.size.width * card.scale / 2 + margin
            && abs(y) <= card.size.height * card.scale / 2 + margin
    }

    // MARK: - Small maths

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    private func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { min(max(value, low), high) }

    private func easeInOut(_ p: CGFloat) -> CGFloat {
        p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }

    /// One step of a damped spring pulling `x` toward `target`.
    private func spring(_ x: inout CGFloat, _ v: inout CGFloat, to target: CGFloat, k: CGFloat, c: CGFloat, dt: CGFloat) {
        v += (-k * (x - target) - c * v) * dt
        x += v * dt
    }
}
