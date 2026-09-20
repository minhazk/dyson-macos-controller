import AppKit
import DysonKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.55)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if let device = model.device {
                        controls(for: device)
                        sensors
                    } else {
                        emptyState
                    }

                    if let error = model.lastError {
                        errorBanner(error)
                    }
                }
                .padding(14)
            }

            Divider()
                .opacity(0.55)

            footer
        }
        .frame(width: 360, height: 620)
        .background(.regularMaterial)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.cyan.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: "wind")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.cyan)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.device?.name ?? "Dyson Controller")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 7, height: 7)
                    Text(connectionLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 1) {
                if let temperature = model.state.roomTemperatureCelsius {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(String(format: "%.1f", temperature))
                            .font(.system(size: 29, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("°C")
                            .font(.system(.subheadline, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("ROOM")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.tertiary)
                } else if model.isConfigured {
                    Image(systemName: "thermometer.medium")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Room temperature unavailable")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func controls(for device: DysonDevice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Controls", systemImage: "slider.horizontal.3")

            powerButton

            VStack(alignment: .leading, spacing: 14) {
                if device.capabilities.fanSpeed {
                    sliderControl(
                        title: "Fan speed",
                        systemImage: "fan",
                        tint: .cyan,
                        value: Double(model.state.fanSpeed ?? 1),
                        range: 1...10,
                        step: 1,
                        minimum: "1",
                        maximum: "10",
                        valueText: { value in
                            model.state.fanSpeed == nil ? "Auto" : String(Int(value.rounded()))
                        },
                        onCommit: { model.setFanSpeed(Int($0.rounded())) }
                    )
                }

                if device.capabilities.targetTemperature {
                    sliderControl(
                        title: "Target temperature",
                        systemImage: "thermometer.medium",
                        tint: .orange,
                        value: model.state.targetTemperatureCelsius ?? 20,
                        range: 1...37,
                        step: 1,
                        minimum: "1°",
                        maximum: "37°",
                        valueText: { value in String(format: "%.0f°C", value) },
                        onCommit: { model.setTargetTemperature($0) }
                    )
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))

            if device.capabilities.autoMode || device.capabilities.heating || device.capabilities.nightMode || device.capabilities.oscillation || device.capabilities.airflowDirection {
                sectionTitle("Modes", systemImage: "sparkles")

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    if device.capabilities.autoMode {
                        ModeButton(title: "Auto", systemImage: "wand.and.stars", tint: .purple, isOn: model.state.autoMode ?? false) {
                            model.setAutoMode(!(model.state.autoMode ?? false))
                        }
                    }

                    if device.capabilities.heating {
                        ModeButton(title: "Heating", systemImage: "thermometer.sun", tint: .orange, isOn: model.state.heating ?? false) {
                            model.setHeatMode(!(model.state.heating ?? false))
                        }
                    }

                    if device.capabilities.nightMode {
                        ModeButton(title: "Night", systemImage: "moon.fill", tint: .indigo, isOn: model.state.nightMode ?? false) {
                            model.setNightMode(!(model.state.nightMode ?? false))
                        }
                    }

                    if device.capabilities.oscillation {
                        ModeButton(title: "Oscillate", systemImage: "arrow.left.and.right", tint: .green, isOn: model.state.oscillating ?? false) {
                            model.setOscillation(!(model.state.oscillating ?? false))
                        }
                    }

                    if device.capabilities.airflowDirection {
                        ModeButton(title: "Front airflow", systemImage: "arrow.forward", tint: .blue, isOn: model.state.frontAirflow ?? true) {
                            model.setAirflow(front: !(model.state.frontAirflow ?? true))
                        }
                    }
                }
            }

            if device.capabilities.oscillation && device.capabilities.oscillationAngle {
                angleControl
            }
        }
    }

    private var powerButton: some View {
        Button {
            model.setPower(!(model.state.isOn ?? false))
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "power")
                    .font(.system(size: 15, weight: .semibold))
                Text("Power")
                    .font(.system(.body, design: .rounded).weight(.semibold))
                Spacer()
                Text((model.state.isOn ?? false) ? "On" : "Off")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Image(systemName: (model.state.isOn ?? false) ? "checkmark.circle.fill" : "circle")
            }
            .foregroundStyle((model.state.isOn ?? false) ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity)
            .background((model.state.isOn ?? false) ? Color.green.opacity(0.82) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Power")
        .accessibilityValue((model.state.isOn ?? false) ? "On" : "Off")
    }

    private func sliderControl(
        title: String,
        systemImage: String,
        tint: Color,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        minimum: String,
        maximum: String,
        valueText: @escaping (Double) -> String,
        onCommit: @escaping (Double) -> Void
    ) -> some View {
        SmoothSlider(
            title: title,
            systemImage: systemImage,
            tint: tint,
            value: value,
            range: range,
            step: step,
            minimum: minimum,
            maximum: maximum,
            valueText: valueText,
            onCommit: onCommit
        )
    }

    private var angleControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Oscillation arc", systemImage: "arrow.left.and.right")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(model.state.oscillationLowAngle ?? 90)°–\(model.state.oscillationHighAngle ?? 270)°")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Stepper(value: Binding(
                    get: { model.state.oscillationLowAngle ?? 90 },
                    set: { model.setOscillationAngles(low: $0, high: model.state.oscillationHighAngle ?? 270) }
                ), in: 5...325, step: 5) {
                    Text("Start \(model.state.oscillationLowAngle ?? 90)°")
                }

                Stepper(value: Binding(
                    get: { model.state.oscillationHighAngle ?? 270 },
                    set: { model.setOscillationAngles(low: model.state.oscillationLowAngle ?? 90, high: $0) }
                ), in: 35...355, step: 5) {
                    Text("End \(model.state.oscillationHighAngle ?? 270)°")
                }
            }
            .font(.caption)
        }
        .padding(12)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var sensors: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Room", systemImage: "house")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                SensorTile(label: "Temperature", value: model.state.roomTemperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "—", symbol: "thermometer", tint: .orange)
                SensorTile(label: "Humidity", value: model.state.humidity.map { String(format: "%.0f%%", $0) } ?? "—", symbol: "humidity", tint: .cyan)
                SensorTile(label: "PM2.5", value: model.state.pm25.map { String(format: "%.0f", $0) } ?? "—", symbol: "aqi.medium", tint: .green)
                SensorTile(label: "PM10", value: model.state.pm10.map { String(format: "%.0f", $0) } ?? "—", symbol: "aqi.low", tint: .green)
                SensorTile(label: "VOC", value: model.state.vocIndex.map { String(format: "%.1f", $0) } ?? "—", symbol: "smoke", tint: .purple)
                SensorTile(label: "NO₂", value: model.state.nitrogenDioxideIndex.map { String(format: "%.1f", $0) } ?? "—", symbol: "aqi.high", tint: .yellow)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "wind")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.cyan)
            Text("No device configured")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text("Add your HP09 in Settings using MyDyson provisioning or the manual local MQTT setup.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                showSettings()
            } label: {
                Label("Open Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(error)
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var footer: some View {
        HStack {
            Button {
                showSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        Label(title.uppercased(), systemImage: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .tracking(0.7)
    }

    private var connectionLabel: String {
        model.state.connection.rawValue.capitalized
    }

    private var connectionColor: Color {
        switch model.state.connection {
        case .connected: return .green
        case .connecting, .reconnecting: return .orange
        case .failed: return .red
        case .disconnected: return .secondary
        }
    }

    private func showSettings() {
        model.showSettingsWindow()
    }
}

private struct SmoothSlider: View {
    let title: String
    let systemImage: String
    let tint: Color
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let minimum: String
    let maximum: String
    let valueText: (Double) -> String
    let onCommit: (Double) -> Void

    @State private var draftValue: Double
    @State private var isDragging = false

    init(
        title: String,
        systemImage: String,
        tint: Color,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        minimum: String,
        maximum: String,
        valueText: @escaping (Double) -> String,
        onCommit: @escaping (Double) -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.value = value
        self.range = range
        self.step = step
        self.minimum = minimum
        self.maximum = maximum
        self.valueText = valueText
        self.onCommit = onCommit
        _draftValue = State(initialValue: value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .frame(width: 18)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(valueText(isDragging ? draftValue : value))
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
            }

            GeometryReader { geometry in
                let fraction = fraction(for: isDragging ? draftValue : value)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.13))
                        .frame(height: 6)

                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(8, geometry.size.width * fraction), height: 6)

                    Circle()
                        .fill(tint)
                        .frame(width: 17, height: 17)
                        .shadow(color: tint.opacity(0.35), radius: 4, y: 1)
                        .offset(x: max(0, min(geometry.size.width - 17, geometry.size.width * fraction - 8.5)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !isDragging {
                                isDragging = true
                            }
                            draftValue = snappedValue(for: gesture.location.x, width: geometry.size.width)
                        }
                        .onEnded { gesture in
                            draftValue = snappedValue(for: gesture.location.x, width: geometry.size.width)
                            isDragging = false
                            onCommit(draftValue)
                        }
                )
            }
            .frame(height: 24)

            HStack {
                Text(minimum)
                Spacer()
                Text(maximum)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .onChange(of: value) { newValue in
            if !isDragging {
                draftValue = newValue
            }
        }
    }

    private func fraction(for value: Double) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(1, max(0, (value - range.lowerBound) / span)))
    }

    private func snappedValue(for location: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return range.lowerBound }
        let rawFraction = min(1, max(0, location / width))
        let rawValue = range.lowerBound + Double(rawFraction) * (range.upperBound - range.lowerBound)
        let stepped = (rawValue / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, stepped))
    }
}

private struct ModeButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isOn ? tint : .secondary)
                    .frame(width: 20, height: 20)
                    .background((isOn ? tint : Color.secondary).opacity(0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.caption)
                    .foregroundStyle(isOn ? tint : Color.secondary.opacity(0.55))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isOn ? tint.opacity(0.13) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(isOn ? tint.opacity(0.32) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct SensorTile: View {
    let label: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 23, height: 23)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(value)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
