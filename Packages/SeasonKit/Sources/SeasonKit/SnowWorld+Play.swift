import Foundation

/// Playing in the snow: scooping snowballs out of drifts, rolling them bigger,
/// throwing them, and stacking three into a snowman.
///
/// Snowballs are made of the same snow as the drifts. Scooping or rolling one
/// takes snow off the pile underneath, and a splat puts it back as a burst of
/// powder that can settle again.
extension SnowWorld {
    // MARK: Interaction

    /// `true` while a snowball or a snowman follows the pointer.
    public var isHolding: Bool { heldID != nil || heldSnowmanID != nil }

    /// Picks up whatever is at `point`: a snowball, a whole snowman (or just
    /// its top ball, with `takingTopBall`), or a fresh snowball packed from the
    /// snow under the pointer (or out of the falling flakes, if there's no
    /// drift there).
    public mutating func grab(at point: SIMD2<Float>, takingTopBall: Bool = false) {
        release(velocity: .zero)
        heldTarget = point

        if let index = snowballs.lastIndex(where: { !$0.isGift && distance($0.position, point) <= $0.radius + 8 }) {
            snowballs[index].state = .held
            snowballs[index].support = nil
            snowballs[index].velocity = .zero
            heldID = snowballs[index].id
            return
        }

        if let index = snowmanIndex(at: point) {
            if takingTopBall {
                takeTopBall(ofSnowman: index)
            } else {
                // Carry the whole snowman, holding it where it was grabbed.
                heldSnowmanID = snowmen[index].id
                heldSnowmanGrip = point - snowmen[index].base
                snowmen[index].support = nil
                snowmen[index].isFalling = false
                snowmen[index].velocity = .zero
            }
            return
        }

        var radius = play.minRadius
        var position = point
        for index in piles.indices {
            guard let top = piles[index].snowTop(at: point.x), point.y >= top - 18, point.y <= piles[index].y + 8 else { continue }
            let area = piles[index].scoop(around: point.x, halfWidth: 12, depth: 60)
            radius = self.radius(forArea: area)
            position.y = min(point.y, top - radius * 0.9)
            break
        }
        let ball = makeSnowball(at: position, radius: radius, state: .held)
        heldID = ball.id
        snowballs.append(ball)
        enforceSnowballLimit()
    }

    /// Moves the held snowball toward `point`.
    public mutating func moveHeld(to point: SIMD2<Float>) {
        heldTarget = point
    }

    /// Lets go of the held snowball, throwing it with `velocity` (points per second).
    public mutating func release(velocity: SIMD2<Float>) {
        if let id = heldSnowmanID {
            heldSnowmanID = nil
            if let index = snowmen.firstIndex(where: { $0.id == id }) {
                // Snowmen are heavy: they don't fly as far as a snowball.
                snowmen[index].isFalling = true
                snowmen[index].velocity = clamped(velocity * play.throwPower * 0.8, maxLength: 2200)
            }
        }
        guard let id = heldID else { return }
        heldID = nil
        guard let index = snowballs.firstIndex(where: { $0.id == id }) else { return }
        snowballs[index].state = .flying
        snowballs[index].velocity = clamped(velocity * play.throwPower, maxLength: 3000)
        snowballs[index].isThrown = length(velocity) > 300
    }

    /// Opens the present at `point`, if there is one, in a shower of sparkles.
    /// Returns where the present was, or `nil` if there wasn't one.
    @discardableResult
    public mutating func openGift(at point: SIMD2<Float>) -> SIMD2<Float>? {
        guard let index = snowballs.lastIndex(where: { $0.isGift && distance($0.position, point) <= $0.radius + 6 }) else { return nil }
        let gift = snowballs.remove(at: index)
        burst(at: gift.position, count: 46, speed: 260, colors: Self.festiveColors)
        burst(at: gift.position, count: 16, speed: 120, colors: [SIMD3(1, 0.85, 0.4)])
        return gift.position
    }

    /// Drops a present, say from Santa's sleigh.
    public mutating func dropGift(at position: SIMD2<Float>, velocity: SIMD2<Float>, style: Int) {
        var gift = Snowball(id: nextBodyID, kind: .gift(style: style), position: position, radius: 11, state: .flying)
        nextBodyID += 1
        gift.velocity = velocity
        snowballs.append(gift)
        let gifts = snowballs.filter(\.isGift)
        if gifts.count > 8, let oldest = gifts.first {
            snowballs.removeAll { $0.id == oldest.id }
        }
    }

    /// Drops a finished snowman from the sky at `x` (somewhere random if `nil`).
    public mutating func buildSnowman(at x: Float? = nil, scale: Float = 1) {
        let size = scale * Float.random(in: 0.85...1.15, using: &random)
        let radii = [24 * size, 17.5 * size, 12.5 * size]
        let x = x ?? Float.random(in: size * 40...max(size * 40 + 1, self.size.x - size * 40), using: &random)
        var snowman = Snowman(
            id: nextBodyID, base: SIMD2(x, -radii.reduce(0, +) * 2), radii: radii, style: UInt32.random(in: 0...UInt32.max, using: &random),
            isFalling: true)
        nextBodyID += 1
        snowman.completedAge = 0
        snowmen.append(snowman)
        enforceSnowmanLimit()
    }

    /// Melts the snowman at `point`. Returns `true` if there was one.
    @discardableResult
    public mutating func meltSnowman(at point: SIMD2<Float>) -> Bool {
        guard let index = snowmanIndex(at: point) else { return false }
        if snowmen[index].id == heldSnowmanID { heldSnowmanID = nil }
        snowmen[index].melt = max(snowmen[index].melt, 0.001)
        return true
    }

    /// Melts every snowman and snowball, quickly and one after another.
    public mutating func meltEverything() {
        heldID = nil
        heldSnowmanID = nil
        for index in snowmen.indices where !snowmen[index].isMelting {
            // A little stagger, so they don't all go at once.
            snowmen[index].melt = 0.001 - Float(index) * 0.06
        }
        for index in snowballs.indices where !snowballs[index].isGift {
            snowballs[index].isMelting = true
            if snowballs[index].state == .held { snowballs[index].state = .flying }
        }
    }

    /// The topmost standing snowman under `point`.
    private func snowmanIndex(at point: SIMD2<Float>) -> Int? {
        snowmen.lastIndex { snowman in
            !snowman.isMelting && snowman.leaningCenters.indices.contains { isPoint(point, onPart: $0, of: snowman) }
        }
    }

    /// Melts every snowman, snowball, present and splat into powder.
    public mutating func clearPlay() {
        heldID = nil
        heldSnowmanID = nil
        for snowman in snowmen {
            for (center, radius) in zip(snowman.leaningCenters, snowman.radii) {
                poof(at: center, radius: radius)
            }
        }
        for ball in snowballs where !ball.isGift {
            poof(at: ball.position, radius: ball.radius)
        }
        snowmen.removeAll()
        snowballs.removeAll()
        splats.removeAll()
        stashedSnowmen.removeAll()
        stashedSnowballs.removeAll()
    }

    /// Topples snowmen and tosses snowballs, as when every window is shaken.
    mutating func shakeLooseEverything() {
        for index in snowmen.indices {
            snowmen[index].tiltVelocity += Float.random(in: -6...6, using: &random)
        }
        for index in snowballs.indices where snowballs[index].state == .resting {
            snowballs[index].state = .flying
            snowballs[index].support = nil
            snowballs[index].velocity = SIMD2(Float.random(in: -120...120, using: &random), -Float.random(in: 250...450, using: &random))
        }
    }

    // MARK: State

    var isPlayAnimating: Bool {
        isHolding
            || !sparkles.isEmpty
            || splats.contains { $0.age < 1 }
            || snowballs.contains { $0.state == .flying || abs($0.velocity.x) > 2 || $0.squash > 0.01 }
            || snowmen.contains {
                $0.melt != 0 || $0.isFalling || abs($0.tiltVelocity) > 0.02 || abs($0.tilt) > 0.01 || ($0.completedAge >= 0 && $0.completedAge < 1)
            }
    }

    /// `true` when nothing from playing is on screen.
    public var hasNoPlayThings: Bool {
        snowballs.isEmpty && snowmen.isEmpty && splats.isEmpty && sparkles.isEmpty
    }

    // MARK: Simulation

    mutating func stepPlay(dt: Float) {
        guard !(snowballs.isEmpty && snowmen.isEmpty && splats.isEmpty && sparkles.isEmpty) else { return }
        stepSnowballs(dt: dt)
        stepSnowmen(dt: dt)
        stepSplats(dt: dt)
        stepSparkles(dt: dt)
    }

    private mutating func stepSnowballs(dt: Float) {
        var index = 0
        while index < snowballs.count {
            snowballs[index].age += dt
            snowballs[index].squash = max(0, snowballs[index].squash - dt * 1.6)

            if snowballs[index].isMelting {
                snowballs[index].radius -= dt * max(14, snowballs[index].radius * 2.2)
                snowballs[index].squash = min(0.3, snowballs[index].squash + dt)
                if snowballs[index].radius < 1.5 {
                    let ball = snowballs.remove(at: index)
                    if ball.state == .resting {
                        leavePuddle(at: ball.position + SIMD2(0, ball.radius), width: 8)
                    }
                    continue
                }
            }
            if snowballs[index].isGift, snowballs[index].age > play.giftLifetime {
                snowballs.remove(at: index)
                continue
            }

            let survived: Bool
            switch snowballs[index].state {
            case .held:
                stepHeld(index, dt: dt)
                survived = true
            case .flying:
                survived = stepFlying(index, dt: dt)
            case .resting:
                stepResting(index, dt: dt)
                survived = true
            }
            if survived { index += 1 }
        }
    }

    /// The held ball follows the pointer. Pressed into a drift, it rolls along
    /// the top of the snow and grows.
    private mutating func stepHeld(_ index: Int, dt: Float) {
        var ball = snowballs[index]
        let previous = ball.position
        ball.position += (heldTarget - ball.position) * min(1, 28 * dt)

        for pileIndex in piles.indices {
            let pile = piles[pileIndex]
            guard
                let top = pile.snowTop(at: ball.position.x),
                ball.position.y + ball.radius > top,
                ball.position.y < pile.y + ball.radius * 0.4
            else { continue }

            ball.position.y = top - ball.radius * 0.9
            let rolled = ball.position.x - previous.x
            ball.rotation += rolled / ball.radius
            if abs(rolled) > 0.2, ball.radius < play.maxRadius {
                let area = piles[pileIndex].scoop(around: ball.position.x, halfWidth: ball.radius * 0.6, depth: min(2.5, abs(rolled) * 0.1 + 0.25))
                grow(&ball, by: area)
            }
            break
        }
        ball.position.y = min(ball.position.y, size.y - ball.radius * 0.9)
        ball.velocity = (ball.position - previous) / dt
        snowballs[index] = ball
    }

    /// Returns `false` if the ball burst and was removed.
    private mutating func stepFlying(_ index: Int, dt: Float) -> Bool {
        var ball = snowballs[index]
        let previous = ball.position
        ball.velocity.y += play.gravity * dt
        ball.velocity *= max(0, 1 - 0.08 * dt)
        ball.position += ball.velocity * dt
        ball.rotation += ball.velocity.x / ball.radius * dt * 0.4

        // The left and right edges of the screen are like glass.
        if ball.position.x - ball.radius < 0, ball.velocity.x < 0 {
            if canSplat(ball, speed: -ball.velocity.x) {
                snowballs.remove(at: index)
                splat(ball, at: SIMD2(0, ball.position.y), normal: SIMD2(1, 0), pile: nil)
                return false
            }
            ball.position.x = ball.radius
            ball.velocity.x *= -0.45
        } else if ball.position.x + ball.radius > size.x, ball.velocity.x > 0 {
            if canSplat(ball, speed: ball.velocity.x) {
                snowballs.remove(at: index)
                splat(ball, at: SIMD2(size.x, ball.position.y), normal: SIMD2(-1, 0), pile: nil)
                return false
            }
            ball.position.x = size.x - ball.radius
            ball.velocity.x *= -0.45
        }

        snowballs[index] = ball
        if !ball.isGift, collideWithSnowmen(index) { return false }
        if !ball.isGift, collideWithSnowballs(index) { return false }
        ball = snowballs[index]

        guard ball.velocity.y > 0, let landing = landingSite(x: ball.position.x, from: previous.y + ball.radius, to: ball.position.y + ball.radius) else {
            if ball.position.y - ball.radius > size.y + 50 {
                snowballs.remove(at: index)
                return false
            }
            return true
        }

        let speed = length(ball.velocity)
        if canSplat(ball, speed: speed) {
            snowballs.remove(at: index)
            splat(ball, at: SIMD2(ball.position.x, landing.top), normal: SIMD2(0, -1), pile: landing.pile)
            return false
        }

        ball.position.y = landing.top - ball.radius * 0.9
        ball.squash = min(0.3, speed / 2000)
        if ball.velocity.y > 220 {
            // Bounce, a little: packed snow is soft.
            ball.velocity.y *= ball.isGift ? -0.35 : -0.22
            ball.velocity.x *= 0.75
        } else {
            ball.state = .resting
            ball.isThrown = false
            ball.velocity.y = 0
            ball.support = support(for: landing, x: ball.position.x)
            ball.supportVelocity = landing.pile.map { piles[$0].velocity } ?? .zero
        }
        snowballs[index] = ball
        return true
    }

    /// Rides along with the window underneath, rolls to a stop, and falls if
    /// its footing disappears or the window is shaken.
    private mutating func stepResting(_ index: Int, dt: Float) {
        var ball = snowballs[index]
        ball.velocity.x *= max(0, 1 - 2.2 * dt)
        let rolled = ball.velocity.x * dt
        ball.rotation += rolled / ball.radius

        switch ball.support {
        case .surface(let id, let offset)?:
            guard let pileIndex = piles.firstIndex(where: { $0.surfaceID == id }) else {
                fall(&ball, velocity: SIMD2(ball.velocity.x, 0))
                break
            }
            let pile = piles[pileIndex]
            let x = pile.minX + offset + rolled
            let shake = pile.velocity - ball.supportVelocity
            ball.supportVelocity = pile.velocity
            guard let top = pile.snowTop(at: x), length(shake) < 650 else {
                fall(&ball, velocity: SIMD2(ball.velocity.x, 0) + ball.supportVelocity - shake)
                break
            }
            if !ball.isGift, abs(rolled) > 0.1, ball.radius < play.maxRadius {
                let area = piles[pileIndex].scoop(around: x, halfWidth: ball.radius * 0.5, depth: min(2, abs(rolled) * 0.1))
                grow(&ball, by: area)
            }
            ball.position = SIMD2(x, top - ball.radius * 0.9)
            ball.support = .surface(id, offset: x - pile.minX)
        case .ground?:
            var x = ball.position.x + rolled
            if x < ball.radius || x > size.x - ball.radius {
                x = min(max(x, ball.radius), size.x - ball.radius)
                ball.velocity.x *= -0.4
            }
            ball.position = SIMD2(x, size.y - ball.radius * 0.95)
        case nil:
            fall(&ball, velocity: ball.velocity)
        }
        snowballs[index] = ball
    }

    private func fall(_ ball: inout Snowball, velocity: SIMD2<Float>) {
        ball.state = .flying
        ball.support = nil
        ball.velocity = velocity
    }

    // MARK: Collisions

    /// Handles a flying ball meeting a snowman: it becomes the next ball of an
    /// unfinished one, or hits it. Returns `true` if the ball was used up.
    private mutating func collideWithSnowmen(_ index: Int) -> Bool {
        let ball = snowballs[index]
        let speed = length(ball.velocity)

        for manIndex in snowmen.indices where !snowmen[manIndex].isMelting {
            let snowman = snowmen[manIndex]
            let centers = snowman.leaningCenters
            for part in centers.indices {
                let center = centers[part]
                let partRadius = snowman.radii[part]
                guard distance(ball.position, center) < ball.radius + partRadius * 0.95 else { continue }

                let isTop = part == centers.count - 1
                let landsOnTop =
                    isTop && ball.velocity.y > 0 && ball.position.y < center.y - partRadius * 0.3 && abs(ball.position.x - center.x) < partRadius * 0.9
                if landsOnTop, !snowman.isComplete, speed < play.splatSpeed, ball.radius <= partRadius * 1.25 {
                    snowballs.remove(at: index)
                    snowmen[manIndex].radii.append(ball.radius)
                    snowmen[manIndex].tiltVelocity += (ball.position.x - center.x) / partRadius * 0.6
                    if snowmen[manIndex].isComplete {
                        snowmen[manIndex].completedAge = 0
                        let head = snowmen[manIndex].leaningCenters.last ?? center
                        burst(at: head, count: 34, speed: 180, colors: [SIMD3(1, 1, 1), SIMD3(1, 0.86, 0.45), SIMD3(0.7, 0.88, 1)])
                    }
                    return true
                }

                // A hit. The snowman wobbles; a hard hit to the head knocks it off.
                let push = ball.velocity.x * (ball.radius / (partRadius + ball.radius)) * 0.004 * Float(part + 1) / Float(centers.count)
                snowmen[manIndex].tiltVelocity += push
                if isTop, snowman.isComplete, speed > 1150 {
                    knockOffHead(ofSnowman: manIndex, velocity: ball.velocity * 0.55 + SIMD2(0, -200))
                }
                let normal = normalized(ball.position - center)
                if canSplat(ball, speed: speed * 0.9) {
                    snowballs.remove(at: index)
                    splat(ball, at: center + normal * partRadius, normal: normal, pile: nil)
                    return true
                }
                bounce(index, off: center, radius: partRadius, normal: normal)
                return false
            }
        }
        return false
    }

    /// Handles a flying ball meeting a resting one: landing gently on top
    /// starts a snowman. Returns `true` if the ball was used up.
    private mutating func collideWithSnowballs(_ index: Int) -> Bool {
        let ball = snowballs[index]
        let speed = length(ball.velocity)

        for otherIndex in snowballs.indices where otherIndex != index {
            let other = snowballs[otherIndex]
            guard other.state == .resting, !other.isGift, distance(ball.position, other.position) < ball.radius + other.radius * 0.95 else { continue }

            let landsOnTop =
                ball.velocity.y > 0 && ball.position.y < other.position.y - other.radius * 0.3 && abs(ball.position.x - other.position.x) < other.radius * 0.9
            if landsOnTop, speed < play.splatSpeed, ball.radius <= other.radius * 1.25 {
                let snowman = Snowman(
                    id: nextBodyID, base: SIMD2(other.position.x, other.position.y + other.radius * 0.9), radii: [other.radius, ball.radius],
                    style: UInt32.random(in: 0...UInt32.max, using: &random), support: other.support, supportVelocity: other.supportVelocity, isFalling: false)
                nextBodyID += 1
                let ids: Set = [ball.id, other.id]
                snowballs.removeAll { ids.contains($0.id) }
                snowmen.append(snowman)
                enforceSnowmanLimit()
                return true
            }

            let normal = normalized(ball.position - other.position)
            if canSplat(ball, speed: speed) {
                snowballs[otherIndex].velocity.x += ball.velocity.x * 0.25 * ball.radius / other.radius
                snowballs.remove(at: index)
                splat(ball, at: other.position + normal * other.radius, normal: normal, pile: nil)
                return true
            }
            snowballs[otherIndex].velocity.x += ball.velocity.x * 0.3 * ball.radius / other.radius
            bounce(index, off: other.position, radius: other.radius, normal: normal)
            return false
        }
        return false
    }

    private mutating func bounce(_ index: Int, off center: SIMD2<Float>, radius: Float, normal: SIMD2<Float>) {
        var ball = snowballs[index]
        ball.position = center + normal * (radius + ball.radius)
        let along = (ball.velocity * normal).sum()
        if along < 0 {
            ball.velocity -= normal * along * 1.4
        }
        ball.velocity *= 0.6
        ball.squash = 0.2
        snowballs[index] = ball
    }

    // MARK: Snowmen

    private mutating func stepSnowmen(dt: Float) {
        var index = 0
        while index < snowmen.count {
            var snowman = snowmen[index]
            snowman.age += dt
            if snowman.completedAge >= 0 { snowman.completedAge += dt }
            if snowman.melt != 0 {
                // A staggered start counts up from below zero first.
                snowman.melt += dt / 1.25
                if snowman.melt >= 1 {
                    snowmen.remove(at: index)
                    leavePuddle(at: snowman.base, width: snowman.radii[0])
                    continue
                }
            }

            if snowman.id == heldSnowmanID {
                carry(&snowman, dt: dt)
            } else if snowman.isFalling {
                let previousY = snowman.base.y
                snowman.velocity.y += play.gravity * dt
                snowman.base += snowman.velocity * dt
                snowman.base.x = min(max(snowman.base.x, snowman.radii[0]), size.x - snowman.radii[0])
                if snowman.velocity.y > 0, let landing = landingSite(x: snowman.base.x, from: previousY, to: snowman.base.y) {
                    let impact = length(snowman.velocity)
                    if impact > 1500 {
                        // Thrown too hard: it comes apart.
                        snowman.base.y = landing.top
                        snowmen.remove(at: index)
                        topple(snowman)
                        continue
                    }
                    snowman.base.y = landing.top + snowman.radii[0] * 0.08
                    snowman.isFalling = false
                    snowman.support = support(for: landing, x: snowman.base.x)
                    snowman.supportVelocity = landing.pile.map { piles[$0].velocity } ?? .zero
                    snowman.velocity = .zero
                    snowman.tiltVelocity += (Float.random(in: -1...1, using: &random)) * min(impact, 1600) / 1600
                } else if snowman.base.y > size.y + 400 {
                    snowmen.remove(at: index)
                    continue
                }
            } else {
                followSupport(&snowman)
            }

            // A wobbly spring that rights itself, unless it leans too far.
            let height = snowman.radii.reduce(0, +) / 60
            let acceleration = -16 * snowman.tilt - 3.2 * snowman.tiltVelocity + 4 * sin(snowman.tilt) * height
            snowman.tiltVelocity += acceleration * dt
            snowman.tilt += snowman.tiltVelocity * dt

            if snowman.id == heldSnowmanID {
                snowman.tilt = min(max(snowman.tilt, -0.6), 0.6)
            } else if abs(snowman.tilt) > 0.8 {
                snowmen.remove(at: index)
                topple(snowman)
                continue
            }
            snowmen[index] = snowman
            index += 1
        }
    }

    /// The carried snowman follows the pointer, swinging a little as it goes.
    private func carry(_ snowman: inout Snowman, dt: Float) {
        let previous = snowman.base
        var target = heldTarget - heldSnowmanGrip
        target.x = min(max(target.x, snowman.radii[0]), size.x - snowman.radii[0])
        target.y = min(target.y, size.y)
        snowman.base += (target - snowman.base) * min(1, 22 * dt)
        let velocity = (snowman.base - previous) / dt
        // Like something held from above: it trails behind the way it's moved.
        snowman.tiltVelocity -= (velocity.x - snowman.velocity.x) * 0.0009
        snowman.velocity = velocity
    }

    private mutating func followSupport(_ snowman: inout Snowman) {
        switch snowman.support {
        case .surface(let id, let offset)?:
            guard let pile = piles.first(where: { $0.surfaceID == id }), let top = pile.snowTop(at: pile.minX + offset) else {
                snowman.isFalling = true
                snowman.support = nil
                snowman.velocity = snowman.supportVelocity
                return
            }
            let change = pile.velocity - snowman.supportVelocity
            snowman.supportVelocity = pile.velocity
            // Moving the window under it makes it lean the other way.
            snowman.tiltVelocity -= change.x * 0.0016
            if change.y < -900 {
                snowman.tiltVelocity += Float.random(in: -3...3, using: &random)
            }
            snowman.base = SIMD2(pile.minX + offset, top + snowman.radii[0] * 0.08)
        case .ground?:
            snowman.base.y = size.y
        case nil:
            snowman.isFalling = true
        }
    }

    /// Takes the top ball off a snowman and puts it in the pointer's hand.
    private mutating func takeTopBall(ofSnowman index: Int) {
        var snowman = snowmen[index]
        guard let center = snowman.leaningCenters.last, let radius = snowman.radii.popLast() else { return }
        snowman.completedAge = -1
        replace(snowmanAt: index, with: snowman)

        let ball = makeSnowball(at: center, radius: radius, state: .held)
        heldID = ball.id
        snowballs.append(ball)
    }

    private mutating func knockOffHead(ofSnowman index: Int, velocity: SIMD2<Float>) {
        var snowman = snowmen[index]
        guard let center = snowman.leaningCenters.last, let radius = snowman.radii.popLast() else { return }
        snowman.completedAge = -1
        replace(snowmanAt: index, with: snowman)

        var head = makeSnowball(at: center, radius: radius, state: .flying)
        head.velocity = velocity
        head.isThrown = true
        snowballs.append(head)
    }

    /// Stores a snowman that lost a ball. Down to one ball, it's just a snowball again.
    private mutating func replace(snowmanAt index: Int, with snowman: Snowman) {
        guard snowman.radii.count < 2 else {
            snowmen[index] = snowman
            return
        }
        snowmen.remove(at: index)
        guard let radius = snowman.radii.first, let center = snowman.leaningCenters.first else { return }
        var ball = makeSnowball(at: center, radius: radius, state: snowman.isFalling ? .flying : .resting)
        ball.support = snowman.support
        ball.supportVelocity = snowman.supportVelocity
        snowballs.append(ball)
    }

    /// Breaks a snowman that leaned too far into tumbling snowballs.
    private mutating func topple(_ snowman: Snowman) {
        let direction: Float = snowman.tilt > 0 ? 1 : -1
        for (part, (center, radius)) in zip(snowman.leaningCenters, snowman.radii).enumerated() {
            var ball = makeSnowball(at: center, radius: radius, state: .flying)
            ball.velocity = snowman.supportVelocity + SIMD2(direction * Float(part + 1) * 70, -40)
            snowballs.append(ball)
        }
        enforceSnowballLimit()
    }

    private func isPoint(_ point: SIMD2<Float>, onPart part: Int, of snowman: Snowman) -> Bool {
        distance(point, snowman.leaningCenters[part]) <= snowman.radii[part] + 4
    }

    // MARK: Splats, sparkles

    private func canSplat(_ ball: Snowball, speed: Float) -> Bool {
        ball.isThrown && !ball.isGift && play.splatsEnabled && speed > play.splatSpeed
    }

    /// Bursts a snowball: a splat where it hit, half its snow added to the
    /// drift it landed on, and the rest flying off as powder.
    private mutating func splat(_ ball: Snowball, at point: SIMD2<Float>, normal: SIMD2<Float>, pile: Int?) {
        let area = Float.pi * ball.radius * ball.radius / play.packing
        var powder = area
        if let pile, let column = piles[pile].column(at: point.x) {
            let spills = piles[pile].deposit(area * 0.5 / configuration.columnWidth, atColumn: column)
            for spill in spills { spawnSpill(spill) }
            powder *= 0.5
        }
        let width = ball.radius * 1.8
        let height = max(2, powder / width)
        let slice = SnowPile.ReleasedSnow(x: point.x + normal.x * height / 2, width: width, top: point.y - height, bottom: point.y)
        spawnSnow(from: [slice], velocity: SIMD2(-ball.velocity.x * 0.12, -abs(ball.velocity.y) * 0.1 - 120) + normal * 140)

        splats.append(Splat(position: point, radius: ball.radius * 1.35, seed: Float.random(in: 0...100, using: &random), normal: normal))
        if splats.count > 24 { splats.removeFirst(splats.count - 24) }
    }

    /// A little puddle of slush that fades where something melted.
    private mutating func leavePuddle(at point: SIMD2<Float>, width: Float) {
        splats.append(Splat(position: point, radius: width * 1.25, seed: Float.random(in: 0...100, using: &random), normal: SIMD2(0, -1)))
        burst(at: point - SIMD2(0, width * 0.6), count: 10, speed: 70, colors: [SIMD3(0.85, 0.93, 1), SIMD3(1, 1, 1)])
    }

    /// A soft puff of powder where something melted away.
    private mutating func poof(at center: SIMD2<Float>, radius: Float) {
        let slice = SnowPile.ReleasedSnow(x: center.x, width: radius * 1.6, top: center.y - radius * 0.5, bottom: center.y + radius * 0.5)
        spawnSnow(from: [slice], velocity: SIMD2(0, -60))
    }

    private mutating func stepSplats(dt: Float) {
        for index in splats.indices {
            splats[index].age += dt
            // Splats on the glass slowly slide down.
            if splats[index].normal.y == 0 {
                splats[index].position.y += dt * 5
            }
        }
        splats.removeAll { $0.age > Splat.lifetime }
    }

    static let festiveColors: [SIMD3<Float>] = [
        SIMD3(1, 0.25, 0.25), SIMD3(0.3, 0.9, 0.4), SIMD3(1, 0.85, 0.3), SIMD3(0.4, 0.7, 1), SIMD3(1, 0.5, 0.85), SIMD3(1, 1, 1),
    ]

    /// Throws out `count` sparkles in every direction.
    public mutating func burst(at point: SIMD2<Float>, count: Int, speed: Float, colors: [SIMD3<Float>]) {
        guard !colors.isEmpty else { return }
        for _ in 0..<count {
            let angle = Float.random(in: 0...(2 * .pi), using: &random)
            let velocity = SIMD2(cos(angle), sin(angle)) * speed * Float.random(in: 0.3...1, using: &random) + SIMD2(0, -speed * 0.35)
            let lifetime = Float.random(in: 0.7...1.5, using: &random)
            sparkles.append(
                Sparkle(
                    position: point, color: colors[Int.random(in: 0..<colors.count, using: &random)], size: Float.random(in: 1.6...3.4, using: &random),
                    life: lifetime, lifetime: lifetime, velocity: velocity, gravity: 260))
        }
        if sparkles.count > 600 { sparkles.removeFirst(sparkles.count - 600) }
    }

    /// Adds one sparkle that drifts gently, like a trail behind a sleigh.
    public mutating func addSparkle(at point: SIMD2<Float>, velocity: SIMD2<Float>, color: SIMD3<Float>, size: Float, lifetime: Float) {
        sparkles.append(Sparkle(position: point, color: color, size: size, life: lifetime, lifetime: lifetime, velocity: velocity, gravity: 30))
        if sparkles.count > 600 { sparkles.removeFirst(sparkles.count - 600) }
    }

    private mutating func stepSparkles(dt: Float) {
        var survivors = 0
        for index in sparkles.indices {
            var sparkle = sparkles[index]
            sparkle.life -= dt
            guard sparkle.life > 0 else { continue }
            sparkle.velocity.y += sparkle.gravity * dt
            sparkle.velocity *= max(0, 1 - 1.4 * dt)
            sparkle.position += sparkle.velocity * dt
            sparkles[survivors] = sparkle
            survivors += 1
        }
        sparkles.removeLast(sparkles.count - survivors)
    }

    // MARK: Surfaces

    /// Where something falling from `fromY` to `toY` at `x` lands: the snow on
    /// a window or the Dock, or the bottom of the screen.
    private func landingSite(x: Float, from fromY: Float, to toY: Float) -> (pile: Int?, top: Float)? {
        var best: (pile: Int?, top: Float)?
        for index in piles.indices {
            guard let top = piles[index].snowTop(at: x), fromY <= top + 0.5, toY >= top else { continue }
            if best == nil || top < best!.top { best = (index, top) }
        }
        if best == nil, toY >= size.y { best = (nil, size.y) }
        return best
    }

    private func support(for landing: (pile: Int?, top: Float), x: Float) -> Support {
        guard let pile = landing.pile else { return .ground }
        return .surface(piles[pile].surfaceID, offset: x - piles[pile].minX)
    }

    /// Called after the piles change: things on windows that went out of sight
    /// are put aside, things on windows that came back are restored, and
    /// things on windows that closed fall.
    mutating func syncPlayWithSurfaces(keeping hiddenIDs: Set<SurfaceID>) {
        let present = Set(piles.map(\.surfaceID))

        for (id, balls) in stashedSnowballs where present.contains(id) {
            snowballs += balls
            stashedSnowballs[id] = nil
        }
        for (id, men) in stashedSnowmen where present.contains(id) {
            snowmen += men
            stashedSnowmen[id] = nil
        }

        guard !(snowballs.isEmpty && snowmen.isEmpty) else { return }
        snowballs.removeAll { ball in
            guard ball.state == .resting, let id = ball.support?.surfaceID, !present.contains(id), hiddenIDs.contains(id) else { return false }
            stashedSnowballs[id, default: []].append(ball)
            return true
        }
        snowmen.removeAll { snowman in
            guard !snowman.isFalling, let id = snowman.support?.surfaceID, !present.contains(id), hiddenIDs.contains(id) else { return false }
            stashedSnowmen[id, default: []].append(snowman)
            return true
        }
        stashedSnowballs = stashedSnowballs.filter { hiddenIDs.contains($0.key) }
        stashedSnowmen = stashedSnowmen.filter { hiddenIDs.contains($0.key) }
    }

    // MARK: Helpers

    private mutating func makeSnowball(at position: SIMD2<Float>, radius: Float, state: Snowball.State) -> Snowball {
        defer { nextBodyID += 1 }
        return Snowball(id: nextBodyID, kind: .snowball, position: position, radius: radius, state: state)
    }

    private func radius(forArea area: Float) -> Float {
        min(play.maxRadius, max(play.minRadius, (area * play.packing / .pi).squareRoot()))
    }

    private func grow(_ ball: inout Snowball, by area: Float) {
        guard area > 0 else { return }
        ball.radius = min(play.maxRadius, (ball.radius * ball.radius + area * play.packing / .pi).squareRoot())
    }

    private mutating func enforceSnowballLimit() {
        let balls = snowballs.filter { !$0.isGift && $0.id != heldID }
        guard balls.count > play.maxSnowballs, let oldest = balls.first else { return }
        snowballs.removeAll { $0.id == oldest.id }
        poof(at: oldest.position, radius: oldest.radius)
    }

    private mutating func enforceSnowmanLimit() {
        while snowmen.count > max(1, play.maxSnowmen) {
            let oldest = snowmen.removeFirst()
            for (center, radius) in zip(oldest.leaningCenters, oldest.radii) {
                poof(at: center, radius: radius)
            }
        }
    }
}

private func normalized(_ vector: SIMD2<Float>) -> SIMD2<Float> {
    let vectorLength = length(vector)
    return vectorLength > 0.0001 ? vector / vectorLength : SIMD2(0, -1)
}
