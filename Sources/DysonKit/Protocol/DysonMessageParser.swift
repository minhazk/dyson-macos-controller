import Foundation

public enum DysonMessageParser {
    public static func parse(_ data: Data) throws -> DysonMessage {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw DysonKitError.invalidMessage
        }

        guard let root = object as? [String: Any], let message = root["msg"] as? String else {
            throw DysonKitError.invalidMessage
        }

        switch message {
        case "CURRENT-STATE", "STATE-CHANGE":
            guard let productState = root["product-state"] as? [String: Any] else {
                throw DysonKitError.missingField("product-state")
            }
            return .state(Self.flatten(productState))
        case "ENVIRONMENTAL-CURRENT-SENSOR-DATA":
            guard let data = root["data"] as? [String: Any] else {
                throw DysonKitError.missingField("data")
            }
            return .environment(Self.flatten(data))
        default:
            return .ignored(message)
        }
    }

    private static func flatten(_ values: [String: Any]) -> [String: String] {
        values.reduce(into: [String: String]()) { result, item in
            let (key, value) = item
            if let string = value as? String {
                result[key] = string
            } else if let number = value as? NSNumber {
                result[key] = number.stringValue
            } else if let history = value as? [Any], let current = history.last {
                if let string = current as? String {
                    result[key] = string
                } else if let number = current as? NSNumber {
                    result[key] = number.stringValue
                }
            }
        }
    }
}
