import Foundation
import Security

public enum DysonConnectionState: String, Codable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case failed
}

public struct DysonCapabilities: Codable, Equatable, Sendable {
    public var power = true
    public var fanSpeed = true
    public var autoMode = true
    public var heating = false
    public var targetTemperature = false
    public var oscillation = false
    public var oscillationAngle = false
    public var airflowDirection = false
    public var nightMode = true
    public var roomTemperature = false
    public var humidity = false
    public var particulateMatter = false
    public var voc = false
    public var nitrogenDioxide = false

    public init() {}

    public static func inferred(model: String, type: String, firmwareCapabilities: [String] = []) -> DysonCapabilities {
        let upper = "\(model) \(type)".uppercased()
        var result = DysonCapabilities()
        result.oscillation = upper.contains("527") || upper.contains("438") || upper.contains("455") || upper.contains("HP") || upper.contains("TP")
        result.oscillationAngle = result.oscillation && firmwareCapabilities.contains("AdvanceOscillationDay1")
        result.airflowDirection = result.oscillation
        result.roomTemperature = true
        result.humidity = true
        result.particulateMatter = upper.contains("527") || upper.contains("438") || upper.contains("358") || upper.contains("HP") || upper.contains("TP") || upper.contains("PH")
        result.voc = result.particulateMatter
        result.nitrogenDioxide = result.particulateMatter
        result.heating = upper.contains("HP") || upper.contains("455") || upper.contains("527")
        result.targetTemperature = result.heating
        return result
    }
}

public struct DysonDevice: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var name: String
    public let serial: String
    public let model: String
    public let type: String
    public let variant: String?
    public var capabilities: DysonCapabilities

    public init(
        name: String,
        serial: String,
        model: String,
        type: String,
        variant: String? = nil,
        capabilities: DysonCapabilities? = nil
    ) {
        self.id = serial
        self.name = name
        self.serial = serial
        self.model = model
        self.type = type
        self.variant = variant
        self.capabilities = capabilities ?? .inferred(model: model, type: type)
    }
}

public struct LocalDeviceConfiguration: Codable, Equatable, Sendable {
    public var host: String?
    public var port: Int
    public var username: String
    public var password: String
    public var mqttRootTopic: String

    public init(host: String? = nil, port: Int = 1883, username: String, password: String, mqttRootTopic: String) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.mqttRootTopic = mqttRootTopic.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

public struct DysonState: Equatable, Sendable {
    public var isOn: Bool?
    public var fanSpeed: Int?
    public var autoMode: Bool?
    public var heating: Bool?
    public var targetTemperatureCelsius: Double?
    public var oscillating: Bool?
    public var oscillationLowAngle: Int?
    public var oscillationHighAngle: Int?
    public var frontAirflow: Bool?
    public var nightMode: Bool?
    public var roomTemperatureCelsius: Double?
    public var humidity: Double?
    public var pm25: Double?
    public var pm10: Double?
    public var vocIndex: Double?
    public var nitrogenDioxideIndex: Double?
    public var connection: DysonConnectionState = .disconnected
    public var lastUpdated: Date?

    public init() {}

    public mutating func apply(_ update: DysonMessage, now: Date = Date()) {
        switch update {
        case .state(let values):
            isOn = values.bool(forKey: "fpwr") ?? isOn
            autoMode = values.bool(forKey: "auto") ?? autoMode
            heating = values.string(forKey: "hmod").map { $0 == "HEAT" } ?? heating
            targetTemperatureCelsius = values.double(forKey: "hmax").map { ($0 / 10.0) - 273.15 } ?? targetTemperatureCelsius
            oscillating = values.string(forKey: "oson").map { $0 == "ON" || $0 == "OION" } ?? oscillating
            oscillationLowAngle = values.int(forKey: "osal") ?? oscillationLowAngle
            oscillationHighAngle = values.int(forKey: "osau") ?? oscillationHighAngle
            frontAirflow = values.bool(forKey: "fdir") ?? frontAirflow
            nightMode = values.bool(forKey: "nmod") ?? nightMode
            if let rawSpeed = values.string(forKey: "fnsp"), rawSpeed != "AUTO" {
                fanSpeed = Int(rawSpeed)
            } else if values.string(forKey: "fnsp") == "AUTO" {
                fanSpeed = nil
            }
        case .environment(let values):
            roomTemperatureCelsius = values.environmentalDouble(forKey: "tact", divisor: 10.0, kelvinToCelsius: true) ?? roomTemperatureCelsius
            humidity = values.environmentalDouble(forKey: "hact") ?? humidity
            pm25 = values.environmentalDouble(forKey: "p25r") ?? values.environmentalDouble(forKey: "pm25") ?? pm25
            pm10 = values.environmentalDouble(forKey: "p10r") ?? values.environmentalDouble(forKey: "pm10") ?? pm10
            vocIndex = values.environmentalDouble(forKey: "va10", divisor: 10.0) ?? vocIndex
            nitrogenDioxideIndex = values.environmentalDouble(forKey: "noxl", divisor: 10.0) ?? nitrogenDioxideIndex
        case .ignored:
            break
        }
        if update.isStateOrEnvironment {
            lastUpdated = now
        }
    }
}

public enum DysonMessage: Equatable, Sendable {
    case state([String: String])
    case environment([String: String])
    case ignored(String)

    public var isStateOrEnvironment: Bool {
        switch self {
        case .state, .environment: return true
        case .ignored: return false
        }
    }
}

extension Dictionary where Key == String, Value == String {
    public func string(forKey key: String) -> String? {
        self[key]
    }

    public func bool(forKey key: String) -> Bool? {
        guard let value = self[key] else { return nil }
        switch value.uppercased() {
        case "ON", "OION", "FAN", "HEAT": return true
        case "OFF", "OIOF", "IDLE": return false
        default: return nil
        }
    }

    public func int(forKey key: String) -> Int? {
        guard let value = self[key] else { return nil }
        return Int(value)
    }

    public func double(forKey key: String) -> Double? {
        guard let value = self[key] else { return nil }
        return Double(value)
    }

    public func environmentalDouble(forKey key: String, divisor: Double = 1.0, kelvinToCelsius: Bool = false) -> Double? {
        guard let raw = self[key], !["OFF", "INIT", "FAIL", "NONE", "off", "init", "fail", "none"].contains(raw) else { return nil }
        guard let number = Double(raw) else { return nil }
        let divided = number / divisor
        return kelvinToCelsius ? divided - 273.15 : divided
    }
}

public enum DysonKitError: LocalizedError, Equatable, Sendable {
    case invalidMessage
    case missingField(String)
    case invalidValue(String)
    case unsupported(String)
    case cloudHTTP(Int, String)
    case cloudResponse(String)
    case keychain(OSStatus)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMessage: return "The device message was not valid JSON."
        case .missingField(let field): return "The device response did not include \(field)."
        case .invalidValue(let value): return "The device returned an invalid value for \(value)."
        case .unsupported(let value): return "This operation is not supported: \(value)."
        case .cloudHTTP(let status, let path): return "Dyson cloud returned HTTP \(status) for \(path)."
        case .cloudResponse(let message): return message
        case .keychain(let status): return "Keychain operation failed (OSStatus \(status))."
        case .transport(let message): return message
        }
    }
}
