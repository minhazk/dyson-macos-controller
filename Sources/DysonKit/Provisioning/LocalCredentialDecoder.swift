import CommonCrypto
import Foundation

public enum LocalCredentialDecoder {
    public static func decryptPassword(_ encrypted: String) throws -> String {
        guard let input = Data(base64Encoded: encrypted) else { throw DysonKitError.invalidValue("local broker credential") }
        let key = Data((1...32).map(UInt8.init))
        let iv = Data(repeating: 0, count: kCCBlockSizeAES128)
        var output = Data(repeating: 0, count: input.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var moved = 0

        let status = output.withUnsafeMutableBytes { outputBytes in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            input.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw DysonKitError.invalidValue("local broker credential") }
        output.removeSubrange(moved..<output.count)

        struct PasswordEnvelope: Decodable {
            let password: String
            enum CodingKeys: String, CodingKey { case password = "apPasswordHash" }
        }
        do {
            return try JSONDecoder().decode(PasswordEnvelope.self, from: output).password
        } catch {
            throw DysonKitError.invalidValue("local broker credential payload")
        }
    }
}

public struct StoredProvisioning: Codable, Equatable, Sendable {
    public let accessToken: String?
    public let device: DysonDevice
    public let mqtt: LocalDeviceConfiguration

    public init(accessToken: String? = nil, device: DysonDevice, mqtt: LocalDeviceConfiguration) {
        self.accessToken = accessToken
        self.device = device
        self.mqtt = mqtt
    }
}
