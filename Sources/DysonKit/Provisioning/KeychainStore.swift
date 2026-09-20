import Foundation
import Security

public final class KeychainStore: @unchecked Sendable {
    private let service: String

    public init(service: String = "community.dyson.macos-controller") {
        self.service = service
    }

    public func save(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw DysonKitError.keychain(addStatus) }
        } else if updateStatus != errSecSuccess {
            throw DysonKitError.keychain(updateStatus)
        }
    }

    public func read(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw DysonKitError.keychain(status) }
        return result as? Data
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw DysonKitError.keychain(status) }
    }

    public func saveCodable<T: Encodable>(_ value: T, account: String) throws {
        try save(JSONEncoder().encode(value), account: account)
    }

    public func readCodable<T: Decodable>(_ type: T.Type, account: String) throws -> T? {
        guard let data = try read(account: account) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }
}
