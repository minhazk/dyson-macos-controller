import Foundation
import Network
import OSLog

private let mqttLogger = Logger(subsystem: "community.dyson.macos-controller", category: "mqtt")

public struct ReconnectBackoff: Sendable, Equatable {
    public private(set) var attempt = 0
    public let maximum: UInt64

    public init(maximum: UInt64 = 60) {
        self.maximum = maximum
    }

    public mutating func reset() {
        attempt = 0
    }

    public mutating func nextDelay() -> UInt64 {
        let delay = min(maximum, UInt64(pow(2.0, Double(attempt))))
        attempt += 1
        return delay
    }
}

public actor LocalMQTTTransport {
    public typealias MessageHandler = @Sendable (Data) -> Void
    public typealias StatusHandler = @Sendable (DysonConnectionState) -> Void
    public typealias ErrorHandler = @Sendable (String) -> Void

    private let configuration: LocalDeviceConfiguration
    private let serial: String
    private var connection: NWConnection?
    private var keepAliveTask: Task<Void, Never>?
    private var environmentalRefreshTask: Task<Void, Never>?
    private var stopped = false
    private var packetIdentifier: UInt16 = 0
    private var receiveBuffer = Data()

    public init(serial: String, configuration: LocalDeviceConfiguration) {
        self.serial = serial
        self.configuration = configuration
    }

    public func run(onMessage: @escaping MessageHandler, onStatus: @escaping StatusHandler, onError: @escaping ErrorHandler) async {
        stopped = false
        var backoff = ReconnectBackoff()

        while !stopped && !Task.isCancelled {
            do {
                onStatus(.connecting)
                try await connectWithTimeout()
                mqttLogger.notice("MQTT TCP and CONNECT handshake completed")
                try await subscribe(to: statusTopic)
                mqttLogger.notice("MQTT status subscription completed")
                backoff.reset()
                onStatus(.connected)
                keepAliveTask?.cancel()
                keepAliveTask = Task { [weak self] in
                    await self?.keepAliveLoop()
                }

                try await publish(topic: commandTopic, payload: try DysonCommandEncoder.requestCurrentState())
                try await publish(topic: commandTopic, payload: try DysonCommandEncoder.requestEnvironmentalData())
                environmentalRefreshTask?.cancel()
                environmentalRefreshTask = Task { [weak self] in
                    await self?.environmentalRefreshLoop()
                }
                try await readMessages(onMessage: onMessage)

                if !stopped && !Task.isCancelled {
                    throw DysonKitError.transport("The MQTT connection closed.")
                }
            } catch {
                mqttLogger.error("MQTT transport failed: \(error.localizedDescription, privacy: .public)")
                onError(error.localizedDescription)
                await shutdownConnection()
                if stopped || Task.isCancelled { break }
                onStatus(.reconnecting)
                let delay = backoff.nextDelay()
                try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            }
        }

        await shutdownConnection()
        onStatus(.disconnected)
    }

    public func stop() async {
        stopped = true
        await shutdownConnection()
    }

    public func publish(_ data: Data) async throws {
        try await publish(topic: commandTopic, payload: data)
    }

    private var commandTopic: String {
        "\(configuration.mqttRootTopic)/\(serial)/command"
    }

    private var statusTopic: String {
        "\(configuration.mqttRootTopic)/\(serial)/status/current"
    }

    private func connect() async throws {
        guard let host = configuration.host, !host.isEmpty,
              let port = NWEndpoint.Port(rawValue: UInt16(configuration.port))
        else {
            throw DysonKitError.transport("A valid local MQTT hostname and port are required.")
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        self.connection = connection
        receiveBuffer.removeAll(keepingCapacity: true)

        try await withTaskCancellationHandler(operation: {
            try await waitUntilReady(connection)
        }, onCancel: {
            connection.cancel()
        })
        mqttLogger.notice("MQTT TCP connection ready")

        var connectBody = Data()
        connectBody.append(try encodeString("MQIsdp"))
        connectBody.append(3) // MQTT 3.1, used by the Dyson local broker.
        connectBody.append(0xC2) // Clean session + username + password.
        connectBody.append(contentsOf: [0, 90]) // 90-second keep-alive.
        // MQTT 3.1 brokers commonly enforce the 23-byte client identifier
        // limit. Dyson clients use the device serial as the identifier.
        connectBody.append(try encodeString(serial))
        connectBody.append(try encodeString(configuration.username))
        connectBody.append(try encodeString(configuration.password))
        try await send(packet(type: 1, flags: 0, body: connectBody))
        mqttLogger.notice("MQTT CONNECT packet sent")

        let response = try await readPacket()
        mqttLogger.notice("MQTT response packet type=\(response.type, privacy: .public) length=\(response.body.count, privacy: .public)")
        guard response.type == 2, response.body.count >= 2 else {
            throw DysonKitError.transport("The Dyson MQTT broker returned an invalid connection response.")
        }
        guard response.body[1] == 0 else {
            throw DysonKitError.transport("The Dyson MQTT broker refused the connection (code \(response.body[1])).")
        }
    }

    private func connectWithTimeout() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.connect()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                throw DysonKitError.transport("MQTT connection timed out after 10 seconds.")
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private func waitUntilReady(_ connection: NWConnection) async throws {
        let gate = ContinuationGate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard gate.claim() else { return }
                    continuation.resume()
                case .failed(let error):
                    guard gate.claim() else { return }
                    continuation.resume(throwing: error)
                case .cancelled:
                    guard gate.claim() else { return }
                    continuation.resume(throwing: DysonKitError.transport("The local MQTT connection was cancelled."))
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue(label: "community.dyson.mqtt"))
        }
    }

    private func subscribe(to topic: String) async throws {
        let identifier = nextPacketIdentifier()
        var body = Data()
        body.append(contentsOf: [UInt8(identifier >> 8), UInt8(identifier & 0xff)])
        body.append(try encodeString(topic))
        body.append(0) // Request QoS 0, matching the Dyson clients.
        try await send(packet(type: 8, flags: 2, body: body))

        while true {
            let response = try await readPacket()
            guard response.type == 9 else { continue }
            guard response.body.count >= 3, response.body[0] == UInt8(identifier >> 8), response.body[1] == UInt8(identifier & 0xff) else {
                throw DysonKitError.transport("The Dyson MQTT broker returned an invalid subscription response.")
            }
            guard response.body[2] != 0x80 else {
                throw DysonKitError.transport("The Dyson MQTT broker refused the status subscription.")
            }
            return
        }
    }

    private func publish(topic: String, payload: Data) async throws {
        var body = try encodeString(topic)
        body.append(payload)
        try await send(packet(type: 3, flags: 0, body: body)) // QoS 0.
    }

    private func readMessages(onMessage: @escaping MessageHandler) async throws {
        while !stopped && !Task.isCancelled {
            let response = try await readPacket()
            switch response.type {
            case 3:
                guard response.body.count >= 2 else { continue }
                let topicLength = Int(response.body[0]) << 8 | Int(response.body[1])
                let payloadStart = 2 + topicLength
                guard response.body.count >= payloadStart else { continue }
                onMessage(Data(response.body[payloadStart...]))
            case 13:
                break // PINGRESP.
            case 12:
                // Be polite if the broker initiates its own keepalive check.
                try await send(packet(type: 13, flags: 0, body: Data()))
            default:
                break
            }
        }
    }

    private func keepAliveLoop() async {
        while !stopped && !Task.isCancelled {
            do {
                // Send well before the 90-second MQTT keepalive expires.
                try await Task.sleep(nanoseconds: 30_000_000_000)
                guard !stopped && !Task.isCancelled else { return }
                try await send(packet(type: 12, flags: 0, body: Data())) // PINGREQ.
                mqttLogger.debug("MQTT keepalive sent")
            } catch is CancellationError {
                return
            } catch {
                mqttLogger.error("MQTT keepalive failed: \(error.localizedDescription, privacy: .public)")
                connection?.cancel()
                return
            }
        }
    }

    private func environmentalRefreshLoop() async {
        while !stopped && !Task.isCancelled {
            do {
                // Dyson publishes the current sensor values in response to a
                // request; refresh them at the same cadence used by the
                // community Dyson integrations.
                try await Task.sleep(nanoseconds: 30_000_000_000)
                guard !stopped && !Task.isCancelled else { return }
                try await publish(topic: commandTopic, payload: try DysonCommandEncoder.requestEnvironmentalData())
                mqttLogger.debug("MQTT environmental data requested")
            } catch is CancellationError {
                return
            } catch {
                mqttLogger.error("MQTT environmental refresh failed: \(error.localizedDescription, privacy: .public)")
                connection?.cancel()
                return
            }
        }
    }

    private func send(_ data: Data) async throws {
        guard let connection else {
            throw DysonKitError.transport("The local MQTT connection is not open.")
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func readPacket() async throws -> (type: UInt8, body: Data) {
        let header = try await readExactly(1).first!
        var multiplier = 1
        var remainingLength = 0

        for _ in 0..<4 {
            let byte = try await readExactly(1).first!
            remainingLength += Int(byte & 0x7f) * multiplier
            if byte & 0x80 == 0 { break }
            multiplier *= 128
            if multiplier > 128 * 128 * 128 { throw DysonKitError.transport("The Dyson MQTT packet was invalid.") }
        }

        return (header >> 4, try await readExactly(remainingLength))
    }

    private func readExactly(_ length: Int) async throws -> Data {
        guard length >= 0 else { throw DysonKitError.transport("The Dyson MQTT packet length was invalid.") }
        while receiveBuffer.count < length {
            guard let connection else {
                throw DysonKitError.transport("The Dyson MQTT connection closed.")
            }
            let chunk = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else if isComplete {
                        continuation.resume(throwing: DysonKitError.transport("The Dyson MQTT connection closed."))
                    } else {
                        continuation.resume(throwing: DysonKitError.transport("The Dyson MQTT broker returned no data."))
                    }
                }
            }
            receiveBuffer.append(chunk)
        }

        let result = Data(receiveBuffer.prefix(length))
        receiveBuffer.removeFirst(length)
        return result
    }

    private func packet(type: UInt8, flags: UInt8, body: Data) -> Data {
        var result = Data([type << 4 | flags])
        result.append(contentsOf: encodeRemainingLength(body.count))
        result.append(body)
        return result
    }

    private func encodeString(_ value: String) throws -> Data {
        let data = Data(value.utf8)
        guard data.count <= Int(UInt16.max) else {
            throw DysonKitError.transport("The MQTT field was too long.")
        }
        var result = Data([UInt8(data.count >> 8), UInt8(data.count & 0xff)])
        result.append(data)
        return result
    }

    private func encodeRemainingLength(_ value: Int) -> [UInt8] {
        var value = value
        var result: [UInt8] = []
        repeat {
            var encoded = UInt8(value % 128)
            value /= 128
            if value > 0 { encoded |= 0x80 }
            result.append(encoded)
        } while value > 0
        return result
    }

    private func nextPacketIdentifier() -> UInt16 {
        packetIdentifier &+= 1
        if packetIdentifier == 0 { packetIdentifier = 1 }
        return packetIdentifier
    }

    private func shutdownConnection() async {
        keepAliveTask?.cancel()
        keepAliveTask = nil
        environmentalRefreshTask?.cancel()
        environmentalRefreshTask = nil
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll(keepingCapacity: true)
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !completed else { return false }
        completed = true
        return true
    }
}
