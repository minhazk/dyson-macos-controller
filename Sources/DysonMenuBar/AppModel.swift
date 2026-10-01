import Combine
import DysonKit
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var device: DysonDevice?
    @Published private(set) var state = DysonState()
    @Published private(set) var lastError: String?
    @Published private(set) var diagnostics: [String] = []
    @Published private(set) var comfortHeatingEnabled = false
    @Published var launchAtLogin = false

    @Published var manualName = "Dyson HP09"
    @Published var manualSerial = ""
    @Published var manualModel = "HP09"
    @Published var manualType = "527K"
    @Published var manualHost = ""
    @Published var manualPort = "1883"
    @Published var manualUsername = ""
    @Published var manualPassword = ""
    @Published var manualRootTopic = "527K"

    @Published var accountEmail = ""
    @Published var accountCountry = "GB"
    @Published var accountPassword = ""
    @Published var accountOTP = ""
    @Published private(set) var accountMessage: String?

    private let keychain = KeychainStore()
    private let api = MyDysonAPI()
    private var challengeID: UUID?
    private var stored: StoredProvisioning?
    private var transport: LocalMQTTTransport?
    private var transportTask: Task<Void, Never>?
    private var comfortHeatingTask: Task<Void, Never>?
    private var comfortHeatingController: ComfortHeatingController?
    private var comfortHeatingTargetCelsius = 24.0
    private var lastComfortCommandAt: Date?
    private var settingsWindowController: SettingsWindowController?

    init() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        loadStoredProvisioning()
        if stored != nil {
            Task { @MainActor [weak self] in
                self?.reconnect()
            }
        }
    }

    deinit {
        let previousTransport = transport
        transportTask?.cancel()
        comfortHeatingTask?.cancel()
        Task { await previousTransport?.stop() }
    }

    var isConfigured: Bool { device != nil && stored != nil }
    var isConnected: Bool { state.connection == .connected }

    func showSettingsWindow() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: self)
        }
        settingsWindowController?.showSettings()
    }

    func reconnect() {
        guard let device, let stored else {
            lastError = "Add a device in Settings before connecting."
            return
        }

        transportTask?.cancel()
        state.connection = .connecting
        appendDiagnostic("Starting local MQTT connection for \(device.model).")

        transportTask = Task { [weak self] in
            var config = stored.mqtt
            if config.host == nil {
                config.host = await BonjourDiscovery.shared.discover(serial: device.serial)
                if config.host == nil {
                    config.host = BonjourDiscovery.fallbackHostname(for: device.serial)
                    if let fallback = config.host {
                        await MainActor.run { self?.appendDiagnostic("Bonjour did not return a host; trying \(fallback).") }
                    }
                }
            }
            guard let host = config.host, !host.isEmpty else {
                await MainActor.run {
                    self?.setConnection(.failed)
                    self?.lastError = "Could not discover the device on the local network. Enter its hostname or IP in Settings."
                    self?.accountMessage = "Provisioned \(device.name), but local discovery failed. Enter the device hostname in Devices settings."
                }
                return
            }
            config.host = host
            let newTransport = LocalMQTTTransport(serial: device.serial, configuration: config)
            await MainActor.run { [weak self] in
                self?.transport = newTransport
                self?.stored = StoredProvisioning(accessToken: stored.accessToken, device: device, mqtt: config)
            }
            await newTransport.run(
                onMessage: { [weak self] data in
                    Task { @MainActor in
                        self?.receive(data)
                    }
                },
                onStatus: { [weak self] status in
                    NSLog("Dyson MQTT state: %@", status.rawValue)
                    Task { @MainActor in
                        self?.setConnection(status)
                        if status == .connected {
                            self?.lastError = nil
                        }
                    }
                },
                onError: { [weak self] message in
                    NSLog("Dyson MQTT connection error: %@", message)
                    Task { @MainActor in
                        self?.lastError = "MQTT connection error: \(message)"
                        self?.accountMessage = "Provisioned \(device.name), but MQTT connection failed: \(message)"
                    }
                }
            )
        }
    }

    func disconnect() {
        transportTask?.cancel()
        let active = transport
        transport = nil
        Task { await active?.stop() }
        setConnection(.disconnected)
    }

    func saveManualSetup() {
        guard !manualSerial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !manualUsername.isEmpty,
              !manualPassword.isEmpty,
              !manualRootTopic.isEmpty,
              let port = Int(manualPort), (1...65535).contains(port)
        else {
            lastError = "Serial, MQTT credentials, root topic, and a valid port are required."
            return
        }

        let newDevice = DysonDevice(name: manualName.isEmpty ? "Dyson device" : manualName, serial: manualSerial.uppercased(), model: manualModel, type: manualType)
        let configuration = LocalDeviceConfiguration(
            host: manualHost.isEmpty ? nil : manualHost,
            port: port,
            username: manualUsername,
            password: manualPassword,
            mqttRootTopic: manualRootTopic
        )
        let provisioning = StoredProvisioning(device: newDevice, mqtt: configuration)
        do {
            try keychain.saveCodable(provisioning, account: "active-provisioning")
            stored = provisioning
            device = newDevice
            state = DysonState()
            lastError = nil
            manualPassword = ""
            appendDiagnostic("Saved manual setup in Keychain.")
            reconnect()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveHostAndReconnect() {
        guard let device, let stored else {
            lastError = "Provision a device before saving a local hostname."
            return
        }
        let host = manualHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            lastError = "Enter the device hostname or IP address first."
            return
        }

        var configuration = stored.mqtt
        configuration.host = host
        let updated = StoredProvisioning(accessToken: stored.accessToken, device: device, mqtt: configuration)
        do {
            try keychain.saveCodable(updated, account: "active-provisioning")
            self.stored = updated
            lastError = nil
            reconnect()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func setPower(_ on: Bool) {
        stopComfortHeatingForManualChange()
        send { try DysonCommandEncoder.power(on) }
    }

    func setFanSpeed(_ speed: Int) {
        stopComfortHeatingForManualChange()
        send { try DysonCommandEncoder.fanSpeed(speed) }
    }

    func setAutoMode(_ enabled: Bool) {
        stopComfortHeatingForManualChange()
        send { try DysonCommandEncoder.autoMode(enabled) }
    }

    func setHeatMode(_ enabled: Bool) {
        stopComfortHeatingForManualChange()
        send { try DysonCommandEncoder.heatMode(enabled) }
    }

    func setTargetTemperature(_ celsius: Double) {
        stopComfortHeatingForManualChange()
        send { try DysonCommandEncoder.targetTemperature(celsius: celsius) }
    }

    func toggleComfortHeating() {
        if comfortHeatingEnabled {
            comfortHeatingEnabled = false
            comfortHeatingTask?.cancel()
            comfortHeatingTask = nil
            comfortHeatingController = nil
            lastComfortCommandAt = nil
            appendDiagnostic("Comfort heating disabled; leaving the device in its current state.")
            return
        }

        guard device?.capabilities.heating == true else {
            lastError = "Comfort heating is not available for this device."
            return
        }

        comfortHeatingTargetCelsius = state.targetTemperatureCelsius ?? 24
        comfortHeatingController = ComfortHeatingController(
            targetTemperatureCelsius: comfortHeatingTargetCelsius,
            hysteresisCelsius: 0.2,
            minimumHeatingDuration: 60,
            minimumIdleDuration: 60
        )
        comfortHeatingEnabled = true
        lastComfortCommandAt = nil
        appendDiagnostic(String(format: "Comfort heating enabled at %.1f°C.", comfortHeatingTargetCelsius))

        comfortHeatingTask?.cancel()
        comfortHeatingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.evaluateComfortHeating()
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                } catch {
                    return
                }
            }
        }
    }
    func setNightMode(_ enabled: Bool) { send { try DysonCommandEncoder.nightMode(enabled) } }
    func setAirflow(front: Bool) { send { try DysonCommandEncoder.airflow(front: front) } }
    func setOscillation(_ enabled: Bool) {
        let low = state.oscillationLowAngle ?? 90
        let high = state.oscillationHighAngle ?? 270
        send { try DysonCommandEncoder.oscillation(enabled: enabled, lowAngle: low, highAngle: high) }
    }
    func setOscillationAngles(low: Int, high: Int) {
        send { try DysonCommandEncoder.oscillation(enabled: true, lowAngle: low, highAngle: high) }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch {
            lastError = "Could not update Launch at Login: \(error.localizedDescription)"
        }
    }

    func beginAccountLogin() {
        guard !accountEmail.isEmpty else { accountMessage = "Enter your MyDyson email first."; return }
        accountMessage = "Requesting a verification code…"
        Task { [weak self] in
            guard let self else { return }
            do {
                let challenge = try await api.beginLogin(email: accountEmail, country: accountCountry)
                await MainActor.run {
                    self.challengeID = challenge
                    self.accountMessage = "Check your email, then enter the OTP code."
                }
            } catch {
                await MainActor.run { self.accountMessage = self.accountLoginErrorMessage(error) }
            }
        }
    }

    func completeAccountLogin() {
        guard let challengeID, !accountEmail.isEmpty, !accountPassword.isEmpty, !accountOTP.isEmpty else {
            accountMessage = "Request a code and enter your password and OTP code."
            return
        }
        accountMessage = "Completing MyDyson login…"
        Task { [weak self] in
            guard let self else { return }
            do {
                let token = try await api.completeLogin(email: accountEmail, password: accountPassword, otp: accountOTP, challengeID: challengeID)
                try keychain.save(Data(token.utf8), account: "mydyson-access-token")
                let cloudDevices = try await api.devices(accessToken: token)
                guard let cloudDevice = cloudDevices.first(where: { $0.connectedConfiguration?.mqtt != nil }) else {
                    await MainActor.run { self.accountMessage = "No Wi‑Fi device with local MQTT credentials was returned." }
                    return
                }
                guard let mqtt = cloudDevice.connectedConfiguration?.mqtt else { return }
                let password = try LocalCredentialDecoder.decryptPassword(mqtt.localBrokerCredentials)
                let kitDevice = DysonDevice(
                    name: cloudDevice.name,
                    serial: cloudDevice.serialNumber,
                    model: cloudDevice.model,
                    type: cloudDevice.type,
                    variant: cloudDevice.variant,
                    capabilities: .inferred(model: cloudDevice.model, type: cloudDevice.type, firmwareCapabilities: cloudDevice.connectedConfiguration?.firmware.capabilities ?? [])
                )
                let provisioning = StoredProvisioning(
                    accessToken: token,
                    device: kitDevice,
                    mqtt: LocalDeviceConfiguration(host: nil, username: cloudDevice.serialNumber, password: password, mqttRootTopic: mqtt.mqttRootTopicLevel)
                )
                try keychain.saveCodable(provisioning, account: "active-provisioning")
                await MainActor.run {
                    self.stored = provisioning
                    self.device = kitDevice
                    self.manualSerial = kitDevice.serial
                    self.manualName = kitDevice.name
                    self.manualModel = kitDevice.model
                    self.manualType = kitDevice.type
                    self.manualUsername = provisioning.mqtt.username
                    self.manualRootTopic = provisioning.mqtt.mqttRootTopic
                    self.accountPassword = ""
                    self.accountOTP = ""
                    self.accountMessage = "Provisioned \(kitDevice.name). Discovering it on the local network…"
                    self.reconnect()
                }
            } catch {
                await MainActor.run { self.accountMessage = self.accountLoginErrorMessage(error) }
            }
        }
    }

    private func accountLoginErrorMessage(_ error: Error) -> String {
        if let dysonError = error as? DysonKitError,
           case .cloudHTTP(401, let path) = dysonError,
           path == "/v3/userregistration/email/userstatus" {
            return "Dyson rejected the account status check. The app will try the OTP request directly; if it still fails, open the official MyDyson app on the same Wi‑Fi and sign in once."
        }
        if let dysonError = error as? DysonKitError,
           case .cloudHTTP(401, let path) = dysonError,
           path == "/v3/userregistration/email/auth" {
            return "Dyson rejected the OTP request. Open the official MyDyson app on the same Wi‑Fi, sign in once, then request a fresh code here."
        }
        if let dysonError = error as? DysonKitError, case .cloudHTTP(400, _) = dysonError {
            return "Dyson rejected the password or OTP. Request a fresh code, then use the newest 6-digit code with your MyDyson password."
        }
        return error.localizedDescription
    }

    private func send(_ builder: @escaping () throws -> Data) {
        guard let transport else {
            lastError = "The device is not connected."
            return
        }
        do {
            let command = try builder()
            Task { [weak self] in
                do {
                    try await transport.publish(command)
                } catch {
                    await MainActor.run { self?.lastError = error.localizedDescription }
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func stopComfortHeatingForManualChange() {
        guard comfortHeatingEnabled else { return }
        comfortHeatingEnabled = false
        comfortHeatingTask?.cancel()
        comfortHeatingTask = nil
        comfortHeatingController = nil
        lastComfortCommandAt = nil
        appendDiagnostic("Comfort heating disabled by a manual control change.")
    }

    private func evaluateComfortHeating() {
        guard comfortHeatingEnabled,
              state.connection == .connected,
              let roomTemperature = state.roomTemperatureCelsius,
              var controller = comfortHeatingController
        else { return }

        let now = Date()
        let action = controller.evaluate(roomTemperatureCelsius: roomTemperature, now: now)
        comfortHeatingController = controller

        switch action {
        case .startHeating:
            sendComfortHeatingCommand(at: now)
            appendDiagnostic(String(format: "Comfort heating started at %.1f°C.", roomTemperature))

        case .stopHeating:
            sendComfortStopCommand(at: now)
            appendDiagnostic(String(format: "Comfort heating stopped at %.1f°C.", roomTemperature))

        case .wait:
            retryComfortCommandIfDeviceDidNotApply(at: now)
        }
    }

    private func sendComfortHeatingCommand(at date: Date) {
        send { try DysonCommandEncoder.comfortHeating(celsius: self.comfortHeatingTargetCelsius) }
        lastComfortCommandAt = date
    }

    private func sendComfortStopCommand(at date: Date) {
        send { try DysonCommandEncoder.power(false) }
        lastComfortCommandAt = date
    }

    private func retryComfortCommandIfDeviceDidNotApply(at date: Date) {
        guard let controller = comfortHeatingController,
              let lastComfortCommandAt,
              date.timeIntervalSince(lastComfortCommandAt) >= 20
        else { return }

        switch controller.phase {
        case .heating where state.isOn != true || state.heating != true:
            sendComfortHeatingCommand(at: date)
            appendDiagnostic("Comfort heating command was not acknowledged; retrying.")
        case .idle where state.isOn == true:
            sendComfortStopCommand(at: date)
            appendDiagnostic("Comfort stop command was not acknowledged; retrying.")
        default:
            break
        }
    }

    private func receive(_ data: Data) {
        do {
            let message = try DysonMessageParser.parse(data)
            state.apply(message)
            if message.isStateOrEnvironment {
                evaluateComfortHeating()
            }
            if case .ignored(let name) = message {
                appendDiagnostic("Ignored MQTT message \(name).")
            }
        } catch {
            appendDiagnostic("Rejected malformed MQTT message.")
        }
    }

    private func setConnection(_ connection: DysonConnectionState) {
        state.connection = connection
        appendDiagnostic("MQTT state: \(connection.rawValue).")
    }

    private func appendDiagnostic(_ message: String) {
        diagnostics.append(message)
        if diagnostics.count > 100 { diagnostics.removeFirst(diagnostics.count - 100) }
    }

    private func loadStoredProvisioning() {
        do {
            stored = try keychain.readCodable(StoredProvisioning.self, account: "active-provisioning")
            device = stored?.device
            if let device, let mqtt = stored?.mqtt {
                manualName = device.name
                manualSerial = device.serial
                manualModel = device.model
                manualType = device.type
                manualHost = mqtt.host ?? ""
                manualPort = String(mqtt.port)
                manualUsername = mqtt.username
                manualRootTopic = mqtt.mqttRootTopic
            }
        } catch {
            lastError = "Could not read saved device configuration from Keychain."
        }
    }
}
