import SwiftUI

/// A single packet blip on the radar.
private struct Blip {
    var angle: Double      // radians
    var radius: Double     // 0...1 (fraction of max range)
    var speed: Double      // radius units per second (positive = outward)
    var hue: UInt32        // protocol color
    var size: Double
    var life: Double
    var maxLife: Double
}

/// State that survives between animation frames (not observed by SwiftUI —
/// TimelineView drives the redraw, and we mutate this freely during drawing).
private final class RadarField {
    var blips: [Blip] = []
    var lastTick: Date?
    let maxBlips = 700

    func spawn(_ event: NetworkEvent) {
        // Stable bearing per remote IP, with a little spread.
        let base = Double(Self.hash(event.remoteIP) % 36000) / 36000.0 * 2 * .pi
        let jitter = Double.random(in: -0.12...0.12)
        let dur = Double.random(in: 1.1...1.9)
        let sizePts = 2.0 + min(7.0, log2(Double(max(2, event.byteCount))) - 4.0)

        let inbound = event.direction == .inbound
        let blip = Blip(
            angle: base + jitter,
            radius: inbound ? 1.0 : 0.0,
            speed: inbound ? -(1.0 / dur) : (1.0 / dur),
            hue: event.proto.hex,
            size: max(2.0, sizePts),
            life: 0,
            maxLife: dur
        )
        blips.append(blip)
        if blips.count > maxBlips { blips.removeFirst(blips.count - maxBlips) }
    }

    func advance(to date: Date) {
        let dt: Double
        if let last = lastTick { dt = min(0.05, date.timeIntervalSince(last)) } else { dt = 0 }
        lastTick = date
        guard dt > 0 else { return }

        for i in blips.indices {
            blips[i].radius += blips[i].speed * dt
            blips[i].life += dt
        }
        blips.removeAll { $0.life >= $0.maxLife || $0.radius < -0.02 || $0.radius > 1.05 }
    }

    static func hash(_ s: String) -> UInt64 {
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h ^= UInt64(b); h = h &* 1099511628211 }
        return h
    }
}

struct RadarView: View {
    let engine: TrafficEngine
    @State private var field = RadarField()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                field.advance(to: timeline.date)
                draw(in: &context, size: size, now: timeline.date)
            }
        }
        .background(Theme.bg)
        .onReceive(engine.pulse) { event in
            if !engine.paused { field.spawn(event) }
        }
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, now: Date) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR = min(size.width, size.height) / 2 * 0.9

        drawGrid(&context, center: center, maxR: maxR)
        drawSweep(&context, center: center, maxR: maxR, now: now)
        drawBlips(&context, center: center, maxR: maxR)
        drawHub(&context, center: center)
    }

    // MARK: - Grid

    private func drawGrid(_ context: inout GraphicsContext, center: CGPoint, maxR: CGFloat) {
        let ringColor = Theme.accent.opacity(0.18)
        for k in 1...4 {
            let r = maxR * CGFloat(k) / 4
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(ringColor), lineWidth: 1)
        }
        // Radial spokes
        for k in 0..<12 {
            let a = CGFloat(k) / 12 * 2 * .pi
            var p = Path()
            p.move(to: center)
            p.addLine(to: CGPoint(x: center.x + cos(a) * maxR, y: center.y + sin(a) * maxR))
            context.stroke(p, with: .color(Theme.accent.opacity(0.08)), lineWidth: 1)
        }
        // Cardinal labels
        let labels: [(String, CGFloat)] = [("N", -.pi / 2), ("E", 0), ("S", .pi / 2), ("W", .pi)]
        for (text, a) in labels {
            let pt = CGPoint(x: center.x + cos(a) * (maxR + 14),
                             y: center.y + sin(a) * (maxR + 14))
            context.draw(Text(text).font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.dim), at: pt)
        }
    }

    // MARK: - Sweep

    private func drawSweep(_ context: inout GraphicsContext, center: CGPoint, maxR: CGFloat, now: Date) {
        let sweepSpeed = 0.6 // revolutions per second-ish
        let baseAngle = now.timeIntervalSinceReferenceDate * sweepSpeed * 2 * .pi
        let trail = 28
        for i in 0..<trail {
            let a = CGFloat(baseAngle - Double(i) * 0.045)
            let alpha = (1.0 - Double(i) / Double(trail)) * 0.5
            var p = Path()
            p.move(to: center)
            p.addLine(to: CGPoint(x: center.x + cos(a) * maxR, y: center.y + sin(a) * maxR))
            context.stroke(p, with: .color(Theme.accent.opacity(alpha)), lineWidth: 2)
        }
    }

    // MARK: - Blips

    private func drawBlips(_ context: inout GraphicsContext, center: CGPoint, maxR: CGFloat) {
        var glow = context
        glow.blendMode = .plusLighter
        for blip in field.blips {
            let ang = CGFloat(blip.angle)
            let r = CGFloat(blip.radius) * maxR
            let x = center.x + cos(ang) * r
            let y = center.y + sin(ang) * r
            let fade = 1.0 - (blip.life / blip.maxLife)
            let color = Color(hex: blip.hue)

            // Tail behind the blip (opposite the direction of travel).
            let tailR = r - CGFloat(blip.speed >= 0 ? 14 : -14)
            let tx = center.x + cos(ang) * tailR
            let ty = center.y + sin(ang) * tailR
            var tail = Path()
            tail.move(to: CGPoint(x: tx, y: ty))
            tail.addLine(to: CGPoint(x: x, y: y))
            glow.stroke(tail, with: .color(color.opacity(0.35 * fade)), lineWidth: 1.5)

            // Glow + core
            let s = CGFloat(blip.size)
            let halo = CGRect(x: x - s, y: y - s, width: s * 2, height: s * 2)
            glow.fill(Path(ellipseIn: halo), with: .color(color.opacity(0.22 * fade)))
            let core = CGRect(x: x - s / 2.4, y: y - s / 2.4, width: s / 1.2, height: s / 1.2)
            glow.fill(Path(ellipseIn: core), with: .color(color.opacity(0.95 * fade)))
        }
    }

    // MARK: - Center (this machine)

    private func drawHub(_ context: inout GraphicsContext, center: CGPoint) {
        var glow = context
        glow.blendMode = .plusLighter
        for (i, radius) in [16.0, 10.0, 5.0].enumerated() {
            let alpha = 0.18 + Double(i) * 0.28
            let rect = CGRect(x: center.x - radius, y: center.y - radius,
                              width: radius * 2, height: radius * 2)
            glow.fill(Path(ellipseIn: rect), with: .color(Theme.accent.opacity(alpha)))
        }
        context.draw(
            Text("YOU").font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.black),
            at: center
        )
    }
}
