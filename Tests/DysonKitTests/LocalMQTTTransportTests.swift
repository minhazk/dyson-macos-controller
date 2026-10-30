import Foundation
import Network
import XCTest
@testable import DysonKit

final class LocalMQTTTransportTests: XCTestCase {
    func testSilentConnectAcknowledgementTimesOutAndReconnects() async throws {
        try await assertRecovery(after: .silentConnect)
    }

    func testSilentSubscriptionAcknowledgementTimesOutAndReconnects() async throws {
        try await assertRecovery(after: .silentSubscribe)
    }

    func testMissingPingResponseReconnectsEvenThoughTCPRemainsOpen() async throws {
        try await assertRecovery(after: .silentPing)
    }

    func testFallsBackToMQTT311WhenBrokerRejectsMQTT31() async throws {
        try await assertRecovery(after: .requiresMQTT311)
    }

    func testCancellationUnblocksPendingConnectAcknowledgement() async throws {
        try await assertCancellation(after: .silentConnect)
    }

    func testCancellationUnblocksConnectedRead() async throws {
        try await assertCancellation(after: .healthy)
    }

    func testHealthyPingResponsesKeepSessionConnected() async throws {
        let broker = try MockMQTTBroker(firstSession: .healthy)
        try await broker.start()
        defer { broker.stop() }
        let connected = expectation(description: "Connected")
        connected.assertForOverFulfill = true
        let pings = expectation(description: "Repeated keepalive replies")
        pings.expectedFulfillmentCount = 3
        broker.onPing = { pings.fulfill() }
        let transport = makeTransport(port: broker.port)
        let task = Task {
            await transport.run(onMessage: { _ in }, onStatus: {
                if $0 == .connected { connected.fulfill() }
            }, onError: { XCTFail($0) })
        }
        await fulfillment(of: [connected, pings], timeout: 4)
        task.cancel()
        await transport.stop()
        await task.value
    }

    func testBackoffRemainsCappedThroughoutLongNetworkOutage() {
        var backoff = ReconnectBackoff()
        for _ in 0..<1_000 {
            XCTAssertLessThanOrEqual(backoff.nextDelay(), 60)
        }
        XCTAssertEqual(backoff.nextDelay(), 60)
        backoff.reset()
        XCTAssertEqual(backoff.nextDelay(), 1)
    }

    private func makeTransport(port: Int) -> LocalMQTTTransport {
        LocalMQTTTransport(
            serial: "TEST-SERIAL",
            configuration: LocalDeviceConfiguration(host: "127.0.0.1", port: port, username: "test", password: "test", mqttRootTopic: "527K"),
            connectionTimeoutNanoseconds: 500_000_000,
            keepAliveIntervalNanoseconds: 150_000_000
        )
    }

    private func assertRecovery(after failure: MockMQTTBroker.Behavior) async throws {
        let broker = try MockMQTTBroker(firstSession: failure)
        try await broker.start()
        defer { broker.stop() }
        let recovering = expectation(description: "Detected failed session")
        let connected = expectation(description: "Connected on a fresh session")
        connected.expectedFulfillmentCount = failure == .silentPing ? 2 : 1
        let received = expectation(description: "Received state after recovery")
        let transport = makeTransport(port: broker.port)
        let task = Task {
            await transport.run(onMessage: { data in
                XCTAssertEqual(String(data: data, encoding: .utf8), #"{"msg":"CURRENT-STATE"}"#)
                received.fulfill()
            }, onStatus: { status in
                if status == .reconnecting { recovering.fulfill() }
                if status == .connected { connected.fulfill() }
            }, onError: { _ in })
        }
        // silentPing initially connects successfully; the state fixture is
        // only sent on the replacement session, proving actual recovery.
        await fulfillment(of: [recovering, connected, received], timeout: 5)
        task.cancel()
        await transport.stop()
        await task.value
    }

    private func assertCancellation(after behavior: MockMQTTBroker.Behavior) async throws {
        let broker = try MockMQTTBroker(firstSession: behavior)
        try await broker.start()
        defer { broker.stop() }
        let waiting = expectation(description: "Pending MQTT read")
        broker.onWaiting = { waiting.fulfill() }
        let stopped = expectation(description: "Cancelled transport exits")
        let transport = makeTransport(port: broker.port)
        let task = Task {
            await transport.run(onMessage: { _ in }, onStatus: { _ in }, onError: { XCTFail($0) })
            stopped.fulfill()
        }
        await fulfillment(of: [waiting], timeout: 3)
        task.cancel()
        await fulfillment(of: [stopped], timeout: 1)
        // Also release sockets if cancellation regresses, keeping failed tests finite.
        await transport.stop()
        await task.value
    }
}

/// A real loopback TCP broker that can leave MQTT reads pending while TCP
/// stays open, reproducing the outage failure without contacting a Dyson.
private final class MockMQTTBroker: @unchecked Sendable {
    enum Behavior { case healthy, silentConnect, silentSubscribe, silentPing, requiresMQTT311 }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "dyson.tests.broker")
    private let firstSession: Behavior
    private var connections: [NWConnection] = []
    var onWaiting: (@Sendable () -> Void)?
    var onPing: (@Sendable () -> Void)?
    var port: Int { Int(listener.port!.rawValue) }

    init(firstSession: Behavior) throws {
        self.firstSession = firstSession
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    self?.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                let behavior = connections.isEmpty || firstSession == .requiresMQTT311 ? firstSession : .healthy
                connections.append(connection)
                connection.start(queue: queue)
                receive(connection, behavior: behavior, buffer: Data(), replacement: connections.count > 1)
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.sync {
            listener.cancel()
            connections.forEach { $0.cancel() }
        }
    }

    private func receive(_ connection: NWConnection, behavior: Behavior, buffer: Data, replacement: Bool) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self, error == nil, !complete, let data else { return }
            var buffer = buffer
            buffer.append(data)
            while buffer.count >= 2 {
                // Parse MQTT's variable-length header, including TCP splits.
                let bytes = [UInt8](buffer)
                var length = 0
                var multiplier = 1
                var offset = 1
                repeat {
                    guard offset < bytes.count else {
                        receive(connection, behavior: behavior, buffer: buffer, replacement: replacement)
                        return
                    }
                    let byte = bytes[offset]
                    length += Int(byte & 0x7f) * multiplier
                    offset += 1
                    if byte & 0x80 == 0 { break }
                    multiplier *= 128
                } while true
                guard bytes.count >= offset + length else { break }
                let type = bytes[0] >> 4
                let body = Array(bytes[offset..<(offset + length)])
                buffer = Data(bytes.dropFirst(offset + length))
                switch type {
                case 1:
                    let protocolNameLength = Int(body[0]) << 8 | Int(body[1])
                    let identifierOffset = protocolNameLength + 6
                    let protocolLevel = body[protocolNameLength + 2]
                    let identifierLength = Int(body[identifierOffset]) << 8 | Int(body[identifierOffset + 1])
                    let identifier = String(decoding: body[(identifierOffset + 2)..<(identifierOffset + 2 + identifierLength)], as: UTF8.self)
                    XCTAssertTrue((1...23).contains(identifierLength))
                    XCTAssertNotEqual(identifier, "TEST-SERIAL", "The controller must have its own MQTT session")
                    if behavior == .requiresMQTT311, protocolLevel != 4 {
                        connection.cancel()
                        return
                    }
                    if behavior != .silentConnect { send([0x20, 2, 0, 0], to: connection) }
                    if behavior == .silentConnect { onWaiting?() }
                case 8:
                    if behavior != .silentSubscribe {
                        send([0x90, 3, body[0], body[1], 0], to: connection)
                        if replacement {
                            let payload = Array(#"{"msg":"CURRENT-STATE"}"#.utf8)
                            send([0x30, UInt8(payload.count + 3), 0, 1, 0x73] + payload, to: connection)
                        }
                        onWaiting?()
                    }
                case 12:
                    if behavior != .silentPing { send([0xd0, 0], to: connection) }
                    onPing?()
                default: break
                }
            }
            receive(connection, behavior: behavior, buffer: buffer, replacement: replacement)
        }
    }

    private func send(_ bytes: [UInt8], to connection: NWConnection) {
        connection.send(content: Data(bytes), completion: .contentProcessed { _ in })
    }
}
