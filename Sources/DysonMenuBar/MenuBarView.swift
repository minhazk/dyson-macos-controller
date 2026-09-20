import AppKit
import DysonKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    private let onHeightChange: (CGFloat) -> Void
    @State private var showSensors = false

    init(model: AppModel, onHeightChange: @escaping (CGFloat) -> Void = { _ in }) {
        self.model = model
        self.onHeightChange = onHeightChange
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.55)

            VStack(alignment: .leading, spacing: 14) {
                if let device = model.device {
                    controls(for: device)
                    if showSensors {
                        sensors
                    }
                } else {
                    emptyState
                }

                if let error = model.lastError {
                    errorBanner(error)
                }
            }
            .padding(14)

            Divider()
                .opacity(0.55)

            footer
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial)
        .preferredColorScheme(.dark)
        .background {
            GeometryReader { geometry in
                Color.clear
                    .preference(key: MenuBarHeightPreferenceKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(MenuBarHeightPreferenceKey.self) { height in
            guard height > 0 else { return }
            onHeightChange(height)
        }
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

            if model.device != nil {
                Button {
                    showSensors.toggle()
                } label: {
                    Image(systemName: showSensors ? "waveform.path.ecg.rectangle.fill" : "waveform.path.ecg")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(showSensors ? .cyan : .secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            showSensors ? Color.cyan.opacity(0.12) : Color.clear,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Air quality details")
                .accessibilityValue(showSensors ? "Shown" : "Hidden")
                .help("Air quality details")
            }

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
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                powerButton

                VStack(spacing: 6) {
                    if device.capabilities.fanSpeed {
                        sliderControl(
                            accessibilityTitle: "Fan speed",
                            systemImage: "fan",
                            tint: .cyan,
                            value: Double(model.state.fanSpeed ?? 1),
                            range: 1...10,
                            step: 1,
                            valueText: { value in
                                model.state.fanSpeed == nil ? "Auto" : String(Int(value.rounded()))
                            },
                            onCommit: { model.setFanSpeed(Int($0.rounded())) }
                        )
                    }

                    if device.capabilities.targetTemperature {
                        sliderControl(
                            accessibilityTitle: "Target temperature",
                            systemImage: "thermometer.medium",
                            tint: .orange,
                            value: model.state.targetTemperatureCelsius ?? 20,
                            range: 1...37,
                            step: 1,
                            valueText: { value in String(format: "%.0f°C", value) },
                            onCommit: { model.setTargetTemperature($0) }
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if device.capabilities.autoMode || device.capabilities.heating || device.capabilities.nightMode || device.capabilities.oscillation || device.capabilities.airflowDirection {
                HStack(spacing: 8) {
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
                .frame(maxWidth: .infinity)
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
            Image(systemName: "power")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle((model.state.isOn ?? false) ? Color.white : Color.primary)
                .frame(width: 56, height: 56)
                .background((model.state.isOn ?? false) ? Color.green.opacity(0.82) : Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Power")
        .accessibilityValue((model.state.isOn ?? false) ? "On" : "Off")
        .help("Power")
    }

    private func sliderControl(
        accessibilityTitle: String,
        systemImage: String,
        tint: Color,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        valueText: @escaping (Double) -> String,
        onCommit: @escaping (Double) -> Void
    ) -> some View {
        CompactSlider(
            accessibilityTitle: accessibilityTitle,
            systemImage: systemImage,
            tint: tint,
            value: value,
            range: range,
            step: step,
            valueText: valueText,
            onCommit: onCommit
        )
    }

    private var angleControl: some View {
        OscillationAnglePicker(
            lowAngle: model.state.oscillationLowAngle,
            highAngle: model.state.oscillationHighAngle,
            isOscillating: model.state.oscillating ?? false,
            onCommit: { low, high in
                model.setOscillationAngles(low: low, high: high)
            },
            onToggle: { enabled in
                model.setOscillation(enabled)
            }
        )
    }

    private var sensors: some View {
        VStack(alignment: .leading, spacing: 10) {
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

private struct MenuBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CompactSlider: View {
    let accessibilityTitle: String
    let systemImage: String
    let tint: Color
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: (Double) -> String
    let onCommit: (Double) -> Void

    @State private var draftValue: Double
    @State private var isDragging = false

    init(
        accessibilityTitle: String,
        systemImage: String,
        tint: Color,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        valueText: @escaping (Double) -> String,
        onCommit: @escaping (Double) -> Void
    ) {
        self.accessibilityTitle = accessibilityTitle
        self.systemImage = systemImage
        self.tint = tint
        self.value = value
        self.range = range
        self.step = step
        self.valueText = valueText
        self.onCommit = onCommit
        _draftValue = State(initialValue: value)
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            GeometryReader { geometry in
                let fraction = fraction(for: isDragging ? draftValue : value)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.13))
                        .frame(height: 5)

                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: max(8, geometry.size.width * fraction), height: 5)

                    Circle()
                        .fill(tint)
                        .frame(width: 15, height: 15)
                        .shadow(color: tint.opacity(0.35), radius: 3)
                        .offset(x: max(0, min(geometry.size.width - 15, geometry.size.width * fraction - 7.5)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            isDragging = true
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

            Text(valueText(isDragging ? draftValue : value))
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .frame(minWidth: 30, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(valueText(isDragging ? draftValue : value))
        .accessibilityAdjustableAction { direction in
            let currentValue = isDragging ? draftValue : value
            let nextValue: Double
            switch direction {
            case .increment:
                nextValue = min(range.upperBound, currentValue + step)
            case .decrement:
                nextValue = max(range.lowerBound, currentValue - step)
            @unknown default:
                return
            }
            draftValue = nextValue
            onCommit(nextValue)
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
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? tint : .secondary)
                .frame(maxWidth: .infinity, minHeight: 42)
                .background(isOn ? tint.opacity(0.13) : Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(isOn ? tint.opacity(0.32) : Color.clear, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .help(title)
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
