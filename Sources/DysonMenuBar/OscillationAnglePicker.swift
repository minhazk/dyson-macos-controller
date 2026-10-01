import DysonKit
import SwiftUI

fileprivate enum OscillationHandle {
    case start
    case end
    case orientation

    var tint: Color {
        switch self {
        case .start: return .green
        case .end: return .orange
        case .orientation: return .cyan
        }
    }
}

private struct OscillationPreset: Identifiable {
    let title: String
    let sweep: Double?

    var id: String { title }
}

struct OscillationAnglePicker: View {
    private let minimumAngle = 5.0
    private let maximumAngle = 355.0
    private let minimumSweep = 30.0
    private let angleStep = 5.0

    private let presets = [
        OscillationPreset(title: "OFF", sweep: nil),
        OscillationPreset(title: "45°", sweep: 45),
        OscillationPreset(title: "90°", sweep: 90),
        OscillationPreset(title: "180°", sweep: 180),
        OscillationPreset(title: "350°", sweep: 350)
    ]

    let lowAngle: Int?
    let highAngle: Int?
    let isOscillating: Bool
    let onCommit: (Int, Int) -> Void
    let onToggle: (Bool) -> Void

    @State private var draftStart: Double
    @State private var draftEnd: Double
    @State private var localEnabled: Bool
    @State private var activeHandle: OscillationHandle = .end
    @State private var isDragging = false

    init(
        lowAngle: Int?,
        highAngle: Int?,
        isOscillating: Bool,
        onCommit: @escaping (Int, Int) -> Void,
        onToggle: @escaping (Bool) -> Void
    ) {
        self.lowAngle = lowAngle
        self.highAngle = highAngle
        self.isOscillating = isOscillating
        self.onCommit = onCommit
        self.onToggle = onToggle
        _draftStart = State(initialValue: Double(lowAngle ?? 90))
        _draftEnd = State(initialValue: Double(highAngle ?? 270))
        _localEnabled = State(initialValue: isOscillating)
    }

    var body: some View {
        VStack(spacing: 10) {
            OscillationDial(
                startAngle: $draftStart,
                endAngle: $draftEnd,
                activeHandle: $activeHandle,
                isEnabled: localEnabled,
                isDragging: isDragging,
                onEditingChanged: { editing in
                    isDragging = editing
                },
                onCommit: { start, end in
                    localEnabled = true
                    onCommit(start, end)
                }
            )
            .frame(height: 236)

            HStack {
                Label("Direction", systemImage: "arrow.left.and.right.circle")
                    .foregroundStyle(.cyan)
                Spacer()
                Text("\(Int((draftStart + draftEnd) / 2))° · \(Int(draftEnd - draftStart))° sweep")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.system(.caption, design: .rounded))

            HStack(spacing: 4) {
                ForEach(presets) { preset in
                    presetButton(preset)
                }
            }
        }
        .padding(10)
        .background(
            Color.black.opacity(0.22),
            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
        )
        .onChange(of: lowAngle) { newValue in
            guard !isDragging else { return }
            draftStart = constrainedStart(Double(newValue ?? 90), end: draftEnd)
        }
        .onChange(of: highAngle) { newValue in
            guard !isDragging else { return }
            draftEnd = constrainedEnd(Double(newValue ?? 270), start: draftStart)
        }
        .onChange(of: isOscillating) { newValue in
            guard !isDragging else { return }
            localEnabled = newValue
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Oscillation angle picker")
    }

    private func presetButton(_ preset: OscillationPreset) -> some View {
        let selected = isSelected(preset)

        return Button {
            apply(preset)
        } label: {
            Text(preset.title)
                .font(.system(.caption, design: .rounded).weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    selected ? Color.white.opacity(0.14) : Color.clear,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(preset.title == "OFF" ? "Oscillation off" : "Oscillation \(preset.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func apply(_ preset: OscillationPreset) {
        guard let sweep = preset.sweep else {
            localEnabled = false
            onToggle(false)
            return
        }

        localEnabled = true
        let midpoint = (draftStart + draftEnd) / 2
        let maximumStart = maximumAngle - sweep
        let candidateStart = midpoint - sweep / 2
        draftStart = snapped(min(maximumStart, max(minimumAngle, candidateStart)))
        draftEnd = min(maximumAngle, draftStart + sweep)
        onCommit(Int(draftStart.rounded()), Int(draftEnd.rounded()))
    }

    private func isSelected(_ preset: OscillationPreset) -> Bool {
        guard let sweep = preset.sweep else { return !localEnabled }
        return localEnabled && abs((draftEnd - draftStart) - sweep) < 0.1
    }

    private func constrainedStart(_ value: Double, end: Double) -> Double {
        min(end - minimumSweep, max(minimumAngle, snapped(value)))
    }

    private func constrainedEnd(_ value: Double, start: Double) -> Double {
        max(start + minimumSweep, min(maximumAngle, snapped(value)))
    }

    private func snapped(_ value: Double) -> Double {
        let stepped = (value / angleStep).rounded() * angleStep
        return min(maximumAngle, max(minimumAngle, stepped))
    }
}

private struct OscillationDial: View {
    private let minimumAngle = 5.0
    private let maximumAngle = 355.0
    private let minimumSweep = 30.0
    private let angleStep = 5.0

    @Binding var startAngle: Double
    @Binding var endAngle: Double
    @Binding var activeHandle: OscillationHandle

    let isEnabled: Bool
    let isDragging: Bool
    let onEditingChanged: (Bool) -> Void
    let onCommit: (Int, Int) -> Void

    @State private var dragHandle: OscillationHandle?
    @State private var dragOriginPoint: CGPoint?
    @State private var dragOriginStart: Double?
    @State private var dragOriginEnd: Double?
    @State private var previousDragAngle: Double?
    @State private var accumulatedRotation = 0.0

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            // Reserve room around the dial for the direction handle at every angle.
            let radius = min(geometry.size.width, geometry.size.height) * 0.36
            let startPoint = point(center: center, radius: radius, angle: startAngle)
            let endPoint = point(center: center, radius: radius, angle: endAngle)

            ZStack {
                OscillationDialCanvas(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    activeAngle: previewAngle,
                    isEnabled: isEnabled,
                    isDragging: isDragging
                )

                PurifierModelView(angle: previewAngle)
                    .frame(width: 112, height: 168)
                    .position(x: center.x, y: center.y - 3)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                orientationHandle(center: center, radius: radius + 18)
                    .zIndex(3)

                handleHitTarget(.start, point: startPoint, center: center, radius: radius)
                    .zIndex(activeHandle == .start ? 2 : 1)

                handleHitTarget(.end, point: endPoint, center: center, radius: radius)
                    .zIndex(activeHandle == .end ? 2 : 1)
            }
        }
    }

    private var previewAngle: Double {
        guard isDragging else { return (startAngle + endAngle) / 2 }
        switch activeHandle {
        case .start: return startAngle
        case .end: return endAngle
        case .orientation: return (startAngle + endAngle) / 2
        }
    }

    private func orientationHandle(center: CGPoint, radius: CGFloat) -> some View {
        let midpoint = (startAngle + endAngle) / 2
        return Image(systemName: "arrow.left.and.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.cyan)
            .rotationEffect(.degrees(midpoint))
            .frame(width: 28, height: 28)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.19, blue: 0.24), Color(red: 0.03, green: 0.07, blue: 0.10)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: Circle()
            )
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(colors: [.cyan.opacity(0.85), .cyan.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
            }
            .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
            .frame(width: 40, height: 40)
            .contentShape(Circle())
            .position(point(center: center, radius: radius, angle: midpoint))
            .gesture(handleGesture(.orientation, center: center, radius: radius))
            .help("Drag to move the whole sweep without changing its width")
            .accessibilityLabel("Oscillation direction")
            .accessibilityValue("\(Int(midpoint)) degrees, \(Int(endAngle - startAngle)) degree sweep")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: shiftSweep(by: angleStep)
                case .decrement: shiftSweep(by: -angleStep)
                @unknown default: return
                }
                onCommit(Int(startAngle.rounded()), Int(endAngle.rounded()))
            }
    }

    private func shiftSweep(by delta: Double) {
        let range = OscillationRange(low: startAngle, high: endAngle).shifted(by: delta)
        startAngle = range.low
        endAngle = range.high
    }

    private func handleHitTarget(
        _ handle: OscillationHandle,
        point: CGPoint,
        center: CGPoint,
        radius: CGFloat
    ) -> some View {
        Circle()
            .fill(handle.tint.opacity(0.001))
            .frame(width: 48, height: 48)
            .contentShape(Circle())
            .position(point)
            .gesture(handleGesture(handle, center: center, radius: radius))
            .accessibilityLabel(handle == .start ? "Oscillation start handle" : "Oscillation end handle")
            .accessibilityValue("\(Int(handle == .start ? startAngle : endAngle)) degrees")
    }

    private func handleGesture(_ handle: OscillationHandle, center: CGPoint, radius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragHandle == nil {
                    dragHandle = handle
                    activeHandle = handle
                    let originAngle = handle == .orientation ? (startAngle + endAngle) / 2 : (handle == .start ? startAngle : endAngle)
                    previousDragAngle = originAngle
                    accumulatedRotation = 0
                    dragOriginPoint = point(center: center, radius: radius, angle: originAngle)
                    dragOriginStart = startAngle
                    dragOriginEnd = endAngle
                    onEditingChanged(true)
                }

                guard dragHandle == handle, let dragOriginPoint else { return }
                let translatedPoint = CGPoint(
                    x: dragOriginPoint.x + value.translation.width,
                    y: dragOriginPoint.y + value.translation.height
                )
                update(handle: handle, angle: angle(for: translatedPoint, center: center))
            }
            .onEnded { value in
                guard dragHandle == handle, let dragOriginPoint else {
                    onEditingChanged(false)
                    return
                }

                let translatedPoint = CGPoint(
                    x: dragOriginPoint.x + value.translation.width,
                    y: dragOriginPoint.y + value.translation.height
                )
                update(handle: handle, angle: angle(for: translatedPoint, center: center))

                let changed = abs(startAngle - (dragOriginStart ?? startAngle)) > 0.1
                    || abs(endAngle - (dragOriginEnd ?? endAngle)) > 0.1
                if changed {
                    onCommit(Int(startAngle.rounded()), Int(endAngle.rounded()))
                }

                dragHandle = nil
                self.dragOriginPoint = nil
                dragOriginStart = nil
                dragOriginEnd = nil
                previousDragAngle = nil
                accumulatedRotation = 0
                onEditingChanged(false)
            }
    }

    private func update(handle: OscillationHandle, angle: Double) {
        switch handle {
        case .orientation:
            guard let originStart = dragOriginStart, let originEnd = dragOriginEnd else { return }
            var delta = angle - (previousDragAngle ?? angle)
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            accumulatedRotation += delta
            previousDragAngle = angle
            let range = OscillationRange(low: originStart, high: originEnd).shifted(by: accumulatedRotation)
            startAngle = range.low
            endAngle = range.high
        case .start:
            startAngle = min(endAngle - minimumSweep, max(minimumAngle, snapped(angle)))
        case .end:
            endAngle = max(startAngle + minimumSweep, min(maximumAngle, snapped(angle)))
        }
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        let radians = (angle - 90) * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }

    private func angle(for point: CGPoint, center: CGPoint) -> Double {
        let radians = atan2(point.x - center.x, -(point.y - center.y))
        let degrees = radians * 180 / .pi
        let normalized = degrees >= 0 ? degrees : degrees + 360
        return normalized
    }

    private func snapped(_ value: Double) -> Double {
        let stepped = (value / angleStep).rounded() * angleStep
        return min(maximumAngle, max(minimumAngle, stepped))
    }
}

private struct OscillationDialCanvas: View {
    let startAngle: Double
    let endAngle: Double
    let activeAngle: Double
    let isEnabled: Bool
    let isDragging: Bool

    var body: some View {
        Canvas(opaque: false, colorMode: .nonLinear, rendersAsynchronously: true) { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.36

            drawDial(in: &context, center: center, radius: radius)
            drawSelection(
                in: &context,
                center: center,
                radius: radius,
                start: startAngle,
                end: endAngle,
                enabled: isEnabled,
                dragging: isDragging
            )
            drawHandle(
                in: &context,
                center: center,
                radius: radius,
                angle: startAngle,
                color: .green,
                isActive: isDragging && abs(activeAngle - startAngle) < 0.1,
                isEnabled: isEnabled
            )
            drawHandle(
                in: &context,
                center: center,
                radius: radius,
                angle: endAngle,
                color: .orange,
                isActive: isDragging && abs(activeAngle - endAngle) < 0.1,
                isEnabled: isEnabled
            )
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.035, blue: 0.05),
                    Color.black.opacity(0.90)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityHidden(true)
    }

    private func drawDial(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        context.fill(disc, with: .color(Color.white.opacity(0.055)))
        context.stroke(disc, with: .color(Color.white.opacity(0.10)), lineWidth: 1)

        var topGuide = Path()
        topGuide.move(to: point(center: center, radius: radius + 3, angle: 0))
        topGuide.addLine(to: point(center: center, radius: radius + 18, angle: 0))
        context.stroke(topGuide, with: .color(.white.opacity(0.18)), lineWidth: 2)
    }

    private func drawSelection(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        start: Double,
        end: Double,
        enabled: Bool,
        dragging: Bool
    ) {
        var sector = Path()
        sector.move(to: center)
        for value in stride(from: start, through: end, by: 3) {
            sector.addLine(to: point(center: center, radius: radius, angle: value))
        }
        sector.addLine(to: point(center: center, radius: radius, angle: end))
        sector.closeSubpath()
        context.fill(sector, with: .color(.white.opacity(enabled ? (dragging ? 0.24 : 0.18) : 0.025)))

        var arc = Path()
        arc.move(to: point(center: center, radius: radius, angle: start))
        for value in stride(from: start, through: end, by: 3) {
            arc.addLine(to: point(center: center, radius: radius, angle: value))
        }
        context.stroke(arc, with: .color(.white.opacity(enabled ? 0.38 : 0.08)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        for value in [start, end] {
            var spoke = Path()
            spoke.move(to: center)
            spoke.addLine(to: point(center: center, radius: radius, angle: value))
            context.stroke(spoke, with: .color(.white.opacity(enabled ? 0.22 : 0.08)), lineWidth: 1)
        }
    }

    private func drawHandle(
        in context: inout GraphicsContext,
        center: CGPoint,
        radius: CGFloat,
        angle: Double,
        color: Color,
        isActive: Bool,
        isEnabled: Bool
    ) {
        let handlePoint = point(center: center, radius: radius, angle: angle)
        let size: CGFloat = isActive ? 20 : 16
        let rect = CGRect(x: handlePoint.x - size / 2, y: handlePoint.y - size / 2, width: size, height: size)
        context.fill(Path(ellipseIn: rect), with: .color(isEnabled ? color : .gray.opacity(0.75)))
        context.stroke(
            Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)),
            with: .color(.white.opacity(isActive ? 0.95 : 0.88)),
            lineWidth: isActive ? 2.5 : 2
        )
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        let radians = (angle - 90) * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }
}
