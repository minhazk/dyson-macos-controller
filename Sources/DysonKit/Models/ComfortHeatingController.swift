import Foundation

public enum ComfortHeatingPhase: Equatable, Sendable {
    case unknown
    case heating
    case idle
}

public enum ComfortHeatingAction: Equatable, Sendable {
    case startHeating
    case stopHeating
    case wait
}

/// A small room-level thermostat that stops the device rather than allowing
/// its built-in thermostat to circulate unheated air at the target.
public struct ComfortHeatingController: Sendable {
    public let targetTemperatureCelsius: Double
    public let hysteresisCelsius: Double
    public let minimumHeatingDuration: TimeInterval
    public let minimumIdleDuration: TimeInterval

    public private(set) var phase: ComfortHeatingPhase = .unknown
    private var lastTransitionAt: Date?

    public init(
        targetTemperatureCelsius: Double,
        hysteresisCelsius: Double = 0.2,
        minimumHeatingDuration: TimeInterval = 60,
        minimumIdleDuration: TimeInterval = 60
    ) {
        self.targetTemperatureCelsius = targetTemperatureCelsius
        self.hysteresisCelsius = hysteresisCelsius
        self.minimumHeatingDuration = minimumHeatingDuration
        self.minimumIdleDuration = minimumIdleDuration
    }

    public mutating func reset() {
        phase = .unknown
        lastTransitionAt = nil
    }

    public mutating func evaluate(roomTemperatureCelsius: Double, now: Date) -> ComfortHeatingAction {
        switch phase {
        case .unknown:
            if roomTemperatureCelsius >= targetTemperatureCelsius {
                transition(to: .idle, at: now)
                return .stopHeating
            } else {
                transition(to: .heating, at: now)
                return .startHeating
            }

        case .heating:
            guard roomTemperatureCelsius >= targetTemperatureCelsius,
                  transitionHasBeenStable(for: minimumHeatingDuration, at: now)
            else { return .wait }

            transition(to: .idle, at: now)
            return .stopHeating

        case .idle:
            guard roomTemperatureCelsius <= targetTemperatureCelsius - hysteresisCelsius,
                  transitionHasBeenStable(for: minimumIdleDuration, at: now)
            else { return .wait }

            transition(to: .heating, at: now)
            return .startHeating
        }
    }

    private mutating func transition(to phase: ComfortHeatingPhase, at date: Date) {
        self.phase = phase
        lastTransitionAt = date
    }

    private func transitionHasBeenStable(for duration: TimeInterval, at date: Date) -> Bool {
        guard let lastTransitionAt else { return true }
        return date.timeIntervalSince(lastTransitionAt) >= duration
    }
}
