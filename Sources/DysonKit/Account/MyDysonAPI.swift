import Foundation

public struct MyDysonAPI: Sendable {
    public let baseURL: URL
    public let country: String
    public let culture: String

    public init(baseURL: URL = URL(string: "https://appapi.cp.dyson.com")!, country: String = "GB", culture: String = "en-US") {
        self.baseURL = baseURL
        self.country = country
        self.culture = culture
    }

    public func beginLogin(email: String, country: String? = nil) async throws -> UUID {
        let selectedCountry = country ?? self.country
        try await provision()
        do {
            let status: UserStatus = try await send(
                path: "/v3/userregistration/email/userstatus",
                method: "POST",
                body: ["email": email],
                query: [URLQueryItem(name: "country", value: selectedCountry)]
            )
            guard status.accountStatus == "ACTIVE" else {
                throw DysonKitError.cloudResponse("This MyDyson account is not active (status: \(status.accountStatus)).")
            }
        } catch let error as DysonKitError {
            // Dyson's status preflight can reject an otherwise usable account
            // until the official mobile app refreshes its account session. The
            // email/auth endpoint is the actual OTP request, so let it decide
            // whether the account can start a challenge.
            guard case .cloudHTTP(401, "/v3/userregistration/email/userstatus") = error else {
                throw error
            }
        }

        let response = try await requestLoginChallenge(email: email, country: selectedCountry)
        guard let challenge = UUID(uuidString: response.challengeId) else {
            throw DysonKitError.cloudResponse("Dyson returned an invalid login challenge.")
        }
        return challenge
    }

    public func completeLogin(email: String, password: String, otp: String, challengeID: UUID) async throws -> String {
        let response: LoginInformation = try await send(
            path: "/v3/userregistration/email/verify",
            method: "POST",
            body: [
                "email": email,
                "password": password,
                "otpCode": otp,
                "challengeId": challengeID.uuidString.lowercased()
            ]
        )
        return response.token
    }

    public func devices(accessToken: String) async throws -> [CloudDevice] {
        try await provision()
        return try await send(path: "/v3/manifest", method: "GET", accessToken: accessToken)
    }

    public func localCredentials(accessToken: String, serial: String) async throws -> CloudIoTCredentials {
        try await provision()
        return try await send(
            path: "/v2/authorize/iot-credentials",
            method: "POST",
            body: ["serial": serial],
            accessToken: accessToken
        )
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        body: [String: String]? = nil,
        accessToken: String? = nil,
        query: [URLQueryItem] = []
    ) async throws -> Response {
        var components = URLComponents(url: baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))), resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let url = components?.url else { throw DysonKitError.cloudResponse("Could not construct the Dyson API URL.") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("android client", forHTTPHeaderField: "User-Agent")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder().encode(body) }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw DysonKitError.cloudResponse("Dyson returned an invalid HTTP response.") }
        guard (200...299).contains(http.statusCode) else { throw DysonKitError.cloudHTTP(http.statusCode, path) }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw DysonKitError.cloudResponse("Dyson returned a response the app could not decode.")
        }
    }

    private func requestLoginChallenge(email: String, country: String) async throws -> LoginChallenge {
        try await send(
            path: "/v3/userregistration/email/auth",
            method: "POST",
            body: ["email": email],
            query: [
                URLQueryItem(name: "country", value: country),
                URLQueryItem(name: "culture", value: culture)
            ]
        )
    }

    private func provision() async throws {
        let _: String = try await send(path: "/v1/provisioningservice/application/Android/version", method: "GET")
    }
}

public struct MyDysonRegion: Identifiable, Equatable, Sendable {
    public let code: String
    public let name: String

    public var id: String { code }

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }

    public static let supported: [MyDysonRegion] = [
        .init(code: "AU", name: "Australia"),
        .init(code: "AT", name: "Austria"),
        .init(code: "BE", name: "Belgium"),
        .init(code: "CA", name: "Canada"),
        .init(code: "CN", name: "Mainland China"),
        .init(code: "HR", name: "Croatia"),
        .init(code: "CZ", name: "Czechia"),
        .init(code: "DK", name: "Denmark"),
        .init(code: "FI", name: "Finland"),
        .init(code: "FR", name: "France"),
        .init(code: "DE", name: "Germany"),
        .init(code: "HK", name: "Hong Kong"),
        .init(code: "HU", name: "Hungary"),
        .init(code: "IN", name: "India"),
        .init(code: "ID", name: "Indonesia"),
        .init(code: "IE", name: "Ireland"),
        .init(code: "IL", name: "Israel"),
        .init(code: "IT", name: "Italy"),
        .init(code: "JP", name: "Japan"),
        .init(code: "LT", name: "Lithuania"),
        .init(code: "MY", name: "Malaysia"),
        .init(code: "MX", name: "Mexico"),
        .init(code: "NL", name: "Netherlands"),
        .init(code: "NZ", name: "New Zealand"),
        .init(code: "NO", name: "Norway"),
        .init(code: "PH", name: "Philippines"),
        .init(code: "PL", name: "Poland"),
        .init(code: "PT", name: "Portugal"),
        .init(code: "RO", name: "Romania"),
        .init(code: "SA", name: "Saudi Arabia"),
        .init(code: "SG", name: "Singapore"),
        .init(code: "SI", name: "Slovenia"),
        .init(code: "KR", name: "South Korea"),
        .init(code: "ES", name: "Spain"),
        .init(code: "SE", name: "Sweden"),
        .init(code: "CH", name: "Switzerland"),
        .init(code: "TW", name: "Taiwan"),
        .init(code: "TH", name: "Thailand"),
        .init(code: "TR", name: "Turkey"),
        .init(code: "AE", name: "United Arab Emirates"),
        .init(code: "GB", name: "United Kingdom"),
        .init(code: "US", name: "United States of America")
    ]
}

public struct CloudDevice: Codable, Equatable, Sendable {
    public let category: String
    public let connectionCategory: String
    public let model: String
    public let name: String
    public let serialNumber: String
    public let type: String
    public let variant: String?
    public let connectedConfiguration: CloudConnectedConfiguration?

    public init(category: String, connectionCategory: String, model: String, name: String, serialNumber: String, type: String, variant: String? = nil, connectedConfiguration: CloudConnectedConfiguration? = nil) {
        self.category = category
        self.connectionCategory = connectionCategory
        self.model = model
        self.name = name
        self.serialNumber = serialNumber
        self.type = type
        self.variant = variant
        self.connectedConfiguration = connectedConfiguration
    }
}

public struct CloudConnectedConfiguration: Codable, Equatable, Sendable {
    public let firmware: CloudFirmware
    public let mqtt: CloudMQTT
}

public struct CloudFirmware: Codable, Equatable, Sendable {
    public let version: String
    public let autoUpdateEnabled: Bool
    public let newVersionAvailable: Bool
    public let capabilities: [String]?
}

public struct CloudMQTT: Codable, Equatable, Sendable {
    public let localBrokerCredentials: String
    public let mqttRootTopicLevel: String
    public let remoteBrokerType: String
}

public struct CloudIoTCredentials: Decodable, Equatable, Sendable {
    public let endpoint: String
    public let clientID: String
    public let customAuthorizerName: String
    public let tokenKey: String
    public let tokenSignature: String
    public let tokenValue: String

    enum CodingKeys: String, CodingKey {
        case endpoint = "Endpoint"
        case credentials = "IoTCredentials"
    }

    enum CredentialKeys: String, CodingKey {
        case clientID = "ClientId"
        case customAuthorizerName = "CustomAuthorizerName"
        case tokenKey = "TokenKey"
        case tokenSignature = "TokenSignature"
        case tokenValue = "TokenValue"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        let nested = try container.nestedContainer(keyedBy: CredentialKeys.self, forKey: .credentials)
        clientID = try nested.decode(String.self, forKey: .clientID)
        customAuthorizerName = try nested.decode(String.self, forKey: .customAuthorizerName)
        tokenKey = try nested.decode(String.self, forKey: .tokenKey)
        tokenSignature = try nested.decode(String.self, forKey: .tokenSignature)
        tokenValue = try nested.decode(String.self, forKey: .tokenValue)
    }
}

private struct LoginChallenge: Decodable {
    let challengeId: String
}

private struct UserStatus: Decodable {
    let accountStatus: String
}

private struct LoginInformation: Decodable {
    let token: String
}
