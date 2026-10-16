import SwiftUI

/// A visual airflow preview. It never polls the device or sends commands.
struct PurifierAirflowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let angle: Double
    let fanSpeed: Int
    let frontAirflow: Bool
    let isActive: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isActive || reduceMotion)) { timeline in
            Canvas { context, size in
                guard isActive else { return }
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                drawAirflow(in: &context, size: size, time: time)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawAirflow(in context: inout GraphicsContext, size: CGSize, time: Double) {
        let origin = CGPoint(x: size.width / 2, y: size.height / 2 - 32)
        let radians = (angle + (frontAirflow ? 0 : 180) - 90) * .pi / 180
        // The upright purifier blows sideways in this elevation view. Its yaw
        // selects the side, rather than projecting the air down toward the dial.
        let horizontal = cos(radians)
        let side: Double = abs(horizontal) < 0.001 ? (frontAirflow ? 1 : -1) : (horizontal > 0 ? 1 : -1)
        let direction = CGVector(dx: side, dy: 0)
        let perpendicular = CGVector(dx: -direction.dy, dy: direction.dx)
        let length = min(size.width, size.height) * 0.74
        let speed = 0.21 + Double(min(10, max(1, fanSpeed))) * 0.025
        var mistContext = context
        mistContext.addFilter(.blur(radius: 2.8))
        var filamentContext = context
        filamentContext.addFilter(.blur(radius: 0.65))

        for strand in 0..<24 {
            let lane = Double(strand) / 23.0 * 2 - 1
            let phase = Double(strand) * 0.137
            let strandLength = length * (0.90 + 0.10 * sin(phase * 9))
            let start = point(origin: origin, direction: direction, perpendicular: perpendicular, length: strandLength, lane: lane, progress: 0, phase: phase, time: time)
            let end = point(origin: origin, direction: direction, perpendicular: perpendicular, length: strandLength, lane: lane, progress: 1, phase: phase, time: time)
            let density = 0.65 + 0.35 * (1 - abs(lane))
            var trail = Path()
            for sample in 0...30 {
                let progress = Double(sample) / 30
                let position = point(origin: origin, direction: direction, perpendicular: perpendicular, length: strandLength, lane: lane, progress: progress, phase: phase, time: time)
                if sample == 0 { trail.move(to: position) } else { trail.addLine(to: position) }
            }

            // A soft, continuous plume underneath the moving filaments gives the
            // air volume, with a gradual fade instead of a hard clipped endpoint.
            let plume = GraphicsContext.Shading.linearGradient(
                Gradient(stops: [
                    .init(color: ControllerStyle.text.opacity(0.02 * density), location: 0),
                    .init(color: ControllerStyle.text.opacity(0.12 * density), location: 0.22),
                    .init(color: ControllerStyle.text.opacity(0.085 * density), location: 0.65),
                    .init(color: ControllerStyle.text.opacity(0), location: 1)
                ]),
                startPoint: start,
                endPoint: end
            )
            mistContext.stroke(trail, with: plume, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))

            let filament = GraphicsContext.Shading.linearGradient(
                Gradient(stops: [
                    .init(color: ControllerStyle.text.opacity(0.04 * density), location: 0),
                    .init(color: ControllerStyle.text.opacity(0.22 * density), location: 0.2),
                    .init(color: ControllerStyle.text.opacity(0.13 * density), location: 0.65),
                    .init(color: ControllerStyle.text.opacity(0), location: 1)
                ]),
                startPoint: start,
                endPoint: end
            )
            filamentContext.stroke(trail, with: filament, style: StrokeStyle(lineWidth: 1.15, lineCap: .round))

            if reduceMotion { continue }

            // Longer, brighter wisps flow through the plume without flashing.
            for streak in 0..<2 {
                let head = (time * speed + phase + Double(streak) * 0.5).truncatingRemainder(dividingBy: 1)
                let tail = max(0, head - 0.32)
                var highlight = Path()
                for sample in 0...12 {
                    let progress = tail + (head - tail) * Double(sample) / 12
                    let position = point(origin: origin, direction: direction, perpendicular: perpendicular, length: strandLength, lane: lane, progress: progress, phase: phase, time: time)
                    if sample == 0 { highlight.move(to: position) } else { highlight.addLine(to: position) }
                }
                let fade = sin(head * .pi)
                let opacity = fade * fade * (0.28 + (1 - abs(lane)) * 0.16)
                mistContext.stroke(highlight, with: .color(ControllerStyle.text.opacity(opacity * 0.4)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                filamentContext.stroke(highlight, with: .color(ControllerStyle.text.opacity(opacity)), style: StrokeStyle(lineWidth: 1.65, lineCap: .round))
            }
        }
    }

    private func point(
        origin: CGPoint,
        direction: CGVector,
        perpendicular: CGVector,
        length: CGFloat,
        lane: Double,
        progress: Double,
        phase: Double,
        time: Double
    ) -> CGPoint {
        let distance = length * progress
        let spread = lane * (10 + 24 * progress * progress)
        let ripple = sin(progress * 7 + phase * 8 - time * 1.4) * 3.5 * progress
        let lateral = spread + ripple
        return CGPoint(
            x: origin.x + direction.dx * distance + perpendicular.dx * lateral,
            y: origin.y + direction.dy * distance + perpendicular.dy * lateral
        )
    }
}
