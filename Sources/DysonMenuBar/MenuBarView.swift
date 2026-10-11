import AppKit
import DysonKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var presentation: PopoverPresentation
    private let onHeightChange: (CGFloat) -> Void
    @State private var showSensors = false

    init(model: AppModel, presentation: PopoverPresentation, onHeightChange: @escaping (CGFloat) -> Void = { _ in }) {
        self.model = model
        self.presentation = presentation
        self.onHeightChange = onHeightChange
    }

    var body: some View {
        VStack(spacing: 0) {
            header

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
                .overlay(ControllerStyle.outline.opacity(0.5))

            footer
        }
        .frame(width: 360)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(ControllerStyle.text)
        .background(ControllerStyle.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ControllerStyle.outline.opacity(0.7), lineWidth: 1)
                .allowsHitTesting(false)
        }
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
                    .fill(ControllerStyle.tileGradient)
                    .frame(width: 40, height: 40)
                Image(systemName: "wind")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(ControllerStyle.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(model.device?.name ?? "Dyson Controller")
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 7, height: 7)
                    Text(connectionLabel)
                        .font(.caption)
                        .foregroundStyle(ControllerStyle.secondary)
                }
            }

            Spacer()

            if model.device != nil {
                Button {
                    showSensors.toggle()
                } label: {
                    Image(systemName: showSensors ? "waveform.path.ecg.rectangle.fill" : "waveform.path.ecg")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(showSensors ? ControllerStyle.text : ControllerStyle.secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            showSensors ? ControllerStyle.raisedSurface : Color.clear,
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
                            .font(.system(size: 29, weight: .semibold))
                            .monospacedDigit()
                        Text("°C")
                            .font(.system(.subheadline).weight(.medium))
                            .foregroundStyle(ControllerStyle.secondary)
                    }
                    Text("ROOM")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(ControllerStyle.secondary)
                } else if model.isConfigured {
                    Image(systemName: "thermometer.medium")
                        .font(.title3)
                        .foregroundStyle(ControllerStyle.secondary)
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

                VStack(spacing: 8) {
                    if device.capabilities.fanSpeed {
                        sliderControl(
                            accessibilityTitle: "Fan speed",
                            title: "Fan speed",
                            systemImage: "fan",
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
                            title: "Target",
                            systemImage: "thermometer.medium",
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
                HStack(spacing: 6) {
                    if device.capabilities.autoMode {
                        ModeButton(title: "Auto", label: "Auto", systemImage: "wand.and.stars", isOn: model.state.autoMode ?? false) {
                            model.setAutoMode(!(model.state.autoMode ?? false))
                        }
                    }

                    if device.capabilities.heating {
                        ModeButton(
                            title: model.state.heating == true ? "Heating" : "Cooling",
                            label: model.state.heating == true ? "Heat" : "Cool",
                            systemImage: model.state.heating == true ? "thermometer.sun" : "snowflake",
                            isOn: model.state.heating != nil,
                            value: model.state.heating == true ? "Heating" : "Cooling"
                        ) {
                            model.setHeatMode(!(model.state.heating ?? false))
                        }
                    }

                    if device.capabilities.nightMode {
                        ModeButton(title: "Night", label: "Night", systemImage: "moon.fill", isOn: model.state.nightMode ?? false) {
                            model.setNightMode(!(model.state.nightMode ?? false))
                        }
                    }

                    if device.capabilities.oscillation {
                        ModeButton(title: "Oscillate", label: "Oscillate", systemImage: "arrow.left.and.right", isOn: model.state.oscillating ?? false) {
                            model.setOscillation(!(model.state.oscillating ?? false))
                        }
                    }

                    if device.capabilities.airflowDirection {
                        ModeButton(title: "Front airflow", label: model.state.frontAirflow == false ? "Rear" : "Front", systemImage: model.state.frontAirflow == false ? "arrow.backward" : "arrow.forward", isOn: model.state.frontAirflow ?? true, value: model.state.frontAirflow == false ? "Rear" : "Front") {
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
                .foregroundStyle((model.state.isOn ?? false) ? ControllerStyle.text : ControllerStyle.secondary)
                .frame(width: 56, height: 56)
                .background(ControllerStyle.tileGradient, in: Circle())
                .overlay {
                    Circle()
                        .strokeBorder((model.state.isOn ?? false) ? ControllerStyle.accent.opacity(0.5) : ControllerStyle.outline, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Power")
        .accessibilityValue((model.state.isOn ?? false) ? "On" : "Off")
        .help("Power")
    }

    private func sliderControl(
        accessibilityTitle: String,
        title: String,
        systemImage: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        valueText: @escaping (Double) -> String,
        onCommit: @escaping (Double) -> Void
    ) -> some View {
        CompactSlider(
            accessibilityTitle: accessibilityTitle,
            title: title,
            systemImage: systemImage,
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
            isAirflowActive: presentation.isVisible && model.isConnected && model.state.isOn == true,
            fanSpeed: model.state.fanSpeed ?? 4,
            frontAirflow: model.state.frontAirflow ?? true,
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
                SensorTile(label: "Temperature", value: model.state.roomTemperatureCelsius.map { String(format: "%.1f°C", $0) } ?? "—", symbol: "thermometer")
                SensorTile(label: "Humidity", value: model.state.humidity.map { String(format: "%.0f%%", $0) } ?? "—", symbol: "humidity")
                SensorTile(label: "PM2.5", value: model.state.pm25.map { String(format: "%.0f", $0) } ?? "—", symbol: "aqi.medium")
                SensorTile(label: "PM10", value: model.state.pm10.map { String(format: "%.0f", $0) } ?? "—", symbol: "aqi.low")
                SensorTile(label: "VOC", value: model.state.vocIndex.map { String(format: "%.1f", $0) } ?? "—", symbol: "smoke")
                SensorTile(label: "NO₂", value: model.state.nitrogenDioxideIndex.map { String(format: "%.1f", $0) } ?? "—", symbol: "aqi.high")
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "wind")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(ControllerStyle.accent)
            Text("No device configured")
                .font(.system(.title3, design: .rounded).weight(.semibold))
            Text("Add your HP09 in Settings using MyDyson provisioning or the manual local MQTT setup.")
                .font(.subheadline)
                .foregroundStyle(ControllerStyle.secondary)
            Button {
                showSettings()
            } label: {
                Label("Open Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(ControllerStyle.sliderFill)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ControllerStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(ControllerStyle.text)
            Text(error)
                .font(.caption)
                .foregroundStyle(ControllerStyle.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(ControllerStyle.raisedSurface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
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
        .foregroundStyle(ControllerStyle.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var connectionLabel: String {
        model.state.connection.rawValue.capitalized
    }

    private var connectionColor: Color {
        switch model.state.connection {
        case .connected: return ControllerStyle.accent
        case .connecting, .reconnecting: return ControllerStyle.secondary
        case .failed, .disconnected: return ControllerStyle.muted
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
    let title: String
    let systemImage: String
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let valueText: (Double) -> String
    let onCommit: (Double) -> Void

    @State private var draftValue: Double
    @State private var isDragging = false

    init(
        accessibilityTitle: String,
        title: String,
        systemImage: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        valueText: @escaping (Double) -> String,
        onCommit: @escaping (Double) -> Void
    ) {
        self.accessibilityTitle = accessibilityTitle
        self.title = title
        self.systemImage = systemImage
        self.value = value
        self.range = range
        self.step = step
        self.valueText = valueText
        self.onCommit = onCommit
        // Seed the drag draft once; live device values remain authoritative when idle.
        _draftValue = State(initialValue: value)
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ControllerStyle.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ControllerStyle.secondary)

                HStack(spacing: 5) {
                    stepButton(systemImage: "minus", delta: -step)

                    GeometryReader { geometry in
                        let fraction = fraction(for: isDragging ? draftValue : value)
                        let travel = max(0, geometry.size.width - 12)

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.black.opacity(0.65))
                                .frame(height: 13)

                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(LinearGradient(colors: [ControllerStyle.sliderFill.opacity(0.75), ControllerStyle.sliderFill], startPoint: .leading, endPoint: .trailing))
                                .frame(width: 6 + travel * fraction, height: 13)

                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(ControllerStyle.outline.opacity(0.7), lineWidth: 0.75)
                                .frame(height: 13)

                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(ControllerStyle.text.gradient)
                                .frame(width: 12, height: 18)
                                .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                                .offset(x: travel * fraction)
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
                    .frame(height: 22)

                    stepButton(systemImage: "plus", delta: step)

                    Text(valueText(isDragging ? draftValue : value))
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(ControllerStyle.text)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
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

    private func stepButton(systemImage: String, delta: Double) -> some View {
        Button {
            let current = isDragging ? draftValue : value
            let next = min(range.upperBound, max(range.lowerBound, current + delta))
            guard next != current else { return }
            draftValue = next
            onCommit(next)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(ControllerStyle.accent)
                .frame(width: 14, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(delta > 0 ? "Increase" : "Decrease") \(accessibilityTitle.lowercased())")
    }

    private func fraction(for value: Double) -> CGFloat {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat(min(1, max(0, (value - range.lowerBound) / span)))
    }

    private func snappedValue(for location: CGFloat, width: CGFloat) -> Double {
        guard width > 12 else { return range.lowerBound }
        let rawFraction = min(1, max(0, (location - 6) / (width - 12)))
        let rawValue = range.lowerBound + Double(rawFraction) * (range.upperBound - range.lowerBound)
        let stepped = (rawValue / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, stepped))
    }
}

private struct ModeButton: View {
    let title: String
    let label: String
    let systemImage: String
    let isOn: Bool
    var value: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.medium)
                    .frame(width: 20, height: 20)
                    .frame(width: 22, height: 22)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .frame(height: 12)
            }
            .foregroundStyle(isOn ? ControllerStyle.text : ControllerStyle.secondary)
            .frame(maxWidth: .infinity, minHeight: 57)
            .background(isOn ? ControllerStyle.tileGradient : LinearGradient(colors: [ControllerStyle.surface, ControllerStyle.surface], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isOn ? ControllerStyle.accent.opacity(0.5) : ControllerStyle.outline.opacity(0.55), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(value ?? (isOn ? "On" : "Off"))
        .help(title)
    }
}

private struct SensorTile: View {
    let label: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ControllerStyle.accent)
                .frame(width: 23, height: 23)
                .background(ControllerStyle.raisedSurface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            Text(value)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)

            Text(label)
                .font(.caption2)
                .foregroundStyle(ControllerStyle.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(ControllerStyle.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
