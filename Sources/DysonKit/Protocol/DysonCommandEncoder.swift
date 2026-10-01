import Foundation

public enum DysonCommandEncoder {
    public static func requestCurrentState(now: Date = Date()) throws -> Data {
        try encode(["msg": "REQUEST-CURRENT-STATE", "time": timestamp(now)])
    }

    public static func requestEnvironmentalData(now: Date = Date()) throws -> Data {
        try encode(["msg": "REQUEST-PRODUCT-ENVIRONMENT-CURRENT-SENSOR-DATA", "time": timestamp(now)])
    }

    public static func stateSet(_ values: [String: String], now: Date = Date()) throws -> Data {
        try encode([
            "msg": "STATE-SET",
            "time": timestamp(now),
            "mode-reason": "LAPP",
            "data": values
        ])
    }

    public static func power(_ on: Bool, now: Date = Date()) throws -> Data {
        try stateSet(["fpwr": on ? "ON" : "OFF"], now: now)
    }

    public static func fanSpeed(_ speed: Int, now: Date = Date()) throws -> Data {
        guard (1...10).contains(speed) else { throw DysonKitError.invalidValue("fan speed") }
        return try stateSet(["fpwr": "ON", "fnsp": String(format: "%04d", speed)], now: now)
    }

    public static func autoMode(_ enabled: Bool, now: Date = Date()) throws -> Data {
        try stateSet(["auto": enabled ? "ON" : "OFF"], now: now)
    }

    public static func heatMode(_ enabled: Bool, now: Date = Date()) throws -> Data {
        try stateSet(["hmod": enabled ? "HEAT" : "OFF"], now: now)
    }

    public static func targetTemperature(celsius: Double, now: Date = Date()) throws -> Data {
        guard (0.85...36.85).contains(celsius) else { throw DysonKitError.invalidValue("target temperature") }
        let kelvinTenths = Int(((celsius + 273.15) * 10.0).rounded())
        return try stateSet(["hmod": "HEAT", "hmax": String(format: "%04d", kelvinTenths)], now: now)
    }

    public static func comfortHeating(celsius: Double, now: Date = Date()) throws -> Data {
        guard (0.85...36.85).contains(celsius) else { throw DysonKitError.invalidValue("target temperature") }
        let kelvinTenths = Int(((celsius + 273.15) * 10.0).rounded())
        return try stateSet([
            "fpwr": "ON",
            "hmod": "HEAT",
            "hmax": String(format: "%04d", kelvinTenths)
        ], now: now)
    }

    public static func oscillation(
        enabled: Bool,
        lowAngle: Int? = nil,
        highAngle: Int? = nil,
        now: Date = Date()
    ) throws -> Data {
        guard enabled else { return try stateSet(["oson": "OFF"], now: now) }
        guard let lowAngle, let highAngle, (5...355).contains(lowAngle), (5...355).contains(highAngle) else {
            throw DysonKitError.invalidValue("oscillation angle")
        }
        guard lowAngle == highAngle || lowAngle + 30 <= highAngle else {
            throw DysonKitError.invalidValue("oscillation angle range")
        }
        return try stateSet([
            "oson": "ON",
            "fpwr": "ON",
            "ancp": "CUST",
            "osal": String(format: "%04d", lowAngle),
            "osau": String(format: "%04d", highAngle)
        ], now: now)
    }

    public static func airflow(front: Bool, now: Date = Date()) throws -> Data {
        try stateSet(["fdir": front ? "ON" : "OFF"], now: now)
    }

    public static func nightMode(_ enabled: Bool, now: Date = Date()) throws -> Data {
        try stateSet(["nmod": enabled ? "ON" : "OFF"], now: now)
    }

    public static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: date)
    }

    private static func encode(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else { throw DysonKitError.invalidMessage }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
