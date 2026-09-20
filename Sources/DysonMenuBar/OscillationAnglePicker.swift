import SwiftUI

fileprivate enum OscillationHandle {
    case start
    case end

    var tint: Color {
        switch self {
        case .start: return .green
        case .end: return .orange
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

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) * 0.40
            let startPoint = point(center: center, radius: radius, angle: startAngle)
            let endPoint = point(center: center, radius: radius, angle: endAngle)

            ZStack {
                OscillationDialCanvas(
                    startAngle: startAngle,
                    endAngle: endAngle,
                    activeAngle: activeHandle == .start ? startAngle : endAngle,
                    isEnabled: isEnabled,
                    isDragging: isDragging
                )

                handleHitTarget(.start, point: startPoint, center: center, radius: radius)
                    .zIndex(activeHandle == .start ? 2 : 1)

                handleHitTarget(.end, point: endPoint, center: center, radius: radius)
                    .zIndex(activeHandle == .end ? 2 : 1)
            }
        }
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
                    let originAngle = handle == .start ? startAngle : endAngle
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
                onEditingChanged(false)
            }
    }

    private func update(handle: OscillationHandle, angle: Double) {
        switch handle {
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
        return min(maximumAngle, max(minimumAngle, snapped(normalized)))
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
            let radius = min(size.width, size.height) * 0.40

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
            drawPurifier(
                in: &context,
                center: center,
                angle: activeAngle,
                isDragging: isDragging
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

    private func drawPurifier(in context: inout GraphicsContext, center: CGPoint, angle: Double, isDragging: Bool) {
        let yaw = (angle - 90) * .pi / 180
        let facing = abs(cos(yaw))
        let side = sin(yaw)
        let headHeight: CGFloat = 94
        let headWidth = 65 * (0.24 + CGFloat(facing) * 0.76)
        let headCenter = CGPoint(x: center.x + CGFloat(side) * 3, y: center.y - 17)
        let baseCenterY = center.y + 53

        let shadow = CGRect(x: center.x - 38, y: baseCenterY + 15, width: 76, height: 11)
        context.fill(Path(ellipseIn: shadow), with: .color(.black.opacity(0.46)))

        let baseRect = CGRect(x: center.x - 32, y: baseCenterY - 15, width: 64, height: 31)
        let base = Path(roundedRect: baseRect, cornerRadius: 8)
        context.fill(
            base,
            with: .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(0.94),
                    Color(red: 0.38, green: 0.44, blue: 0.50),
                    Color.white.opacity(0.78)
                ]),
                startPoint: CGPoint(x: baseRect.minX, y: baseRect.minY),
                endPoint: CGPoint(x: baseRect.maxX, y: baseRect.maxY)
            )
        )
        context.stroke(base, with: .color(.white.opacity(0.36)), lineWidth: 1)

        let vents = Path { path in
            for row in 0..<4 {
                for column in 0..<8 {
                    let x = baseRect.minX + 9 + CGFloat(column) * 6.3
                    let y = baseRect.minY + 11 + CGFloat(row) * 4.5
                    path.addEllipse(in: CGRect(x: x, y: y, width: 1.8, height: 1.5))
                }
            }
        }
        context.fill(vents, with: .color(.black.opacity(0.34)))

        let displayWidth = 17 * (0.48 + CGFloat(facing) * 0.52)
        let displayRect = CGRect(x: center.x - displayWidth / 2, y: baseRect.minY + 4, width: displayWidth, height: 7)
        context.fill(Path(ellipseIn: displayRect), with: .color(.black.opacity(0.78)))
        context.fill(Path(ellipseIn: CGRect(x: center.x - 1.7, y: displayRect.midY - 1.7, width: 3.4, height: 3.4)), with: .color(.cyan.opacity(0.85)))

        let stem = Path { path in
            path.move(to: CGPoint(x: center.x - 6, y: headCenter.y + headHeight / 2 - 1))
            path.addLine(to: CGPoint(x: center.x + 6, y: headCenter.y + headHeight / 2 - 1))
            path.addLine(to: CGPoint(x: center.x + 10, y: baseRect.minY + 4))
            path.addLine(to: CGPoint(x: center.x - 10, y: baseRect.minY + 4))
            path.closeSubpath()
        }
        context.fill(stem, with: .color(.white.opacity(0.72)))

        let outerRect = CGRect(x: headCenter.x - headWidth / 2, y: headCenter.y - headHeight / 2, width: headWidth, height: headHeight)
        let innerRect = outerRect.insetBy(dx: max(5, headWidth * 0.22), dy: 17)
        let outerRadius = min(20, headWidth * 0.38)
        let innerRadius = min(13, innerRect.width * 0.42)

        context.fill(Path(roundedRect: innerRect, cornerRadius: innerRadius), with: .color(.black.opacity(0.42)))

        var ring = Path()
        ring.addRoundedRect(in: outerRect, cornerSize: CGSize(width: outerRadius, height: outerRadius), style: .continuous)
        ring.addRoundedRect(in: innerRect, cornerSize: CGSize(width: innerRadius, height: innerRadius), style: .continuous)
        context.fill(
            ring,
            with: .linearGradient(
                Gradient(colors: [
                    Color.white.opacity(isDragging ? 0.99 : 0.92),
                    Color(red: 0.60, green: 0.66, blue: 0.72),
                    Color.white.opacity(0.78)
                ]),
                startPoint: CGPoint(x: outerRect.minX, y: outerRect.minY),
                endPoint: CGPoint(x: outerRect.maxX, y: outerRect.maxY)
            ),
            style: FillStyle(eoFill: true)
        )
        context.stroke(Path(roundedRect: outerRect, cornerRadius: outerRadius), with: .color(.white.opacity(0.92)), lineWidth: 1)

        let highlight = CGRect(x: outerRect.minX + max(2, headWidth * 0.11), y: outerRect.minY + 8, width: max(1.5, headWidth * 0.13), height: outerRect.height - 16)
        context.fill(Path(roundedRect: highlight, cornerRadius: 2), with: .color(.white.opacity(0.30)))
    }

    private func point(center: CGPoint, radius: CGFloat, angle: Double) -> CGPoint {
        let radians = (angle - 90) * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }
}
