import SwiftUI
import DysonKit

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TabView {
            deviceSettings
                .tabItem { Label("Devices", systemImage: "fan") }
            accountSettings
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            diagnostics
                .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
            about
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 600, height: 470)
        .padding()
    }

    private var deviceSettings: some View {
        Form {
            Section("Active device") {
                if let device = model.device {
                    LabeledContent("Name", value: device.name)
                    LabeledContent("Model", value: "\(device.model) / \(device.type)")
                    LabeledContent("Serial", value: device.serial)
                    LabeledContent("Connection", value: model.state.connection.rawValue.capitalized)
                    TextField("Hostname or IP", text: $model.manualHost)
                    HStack {
                        Button("Reconnect") { model.reconnect() }
                        Button("Disconnect") { model.disconnect() }
                        Button("Save host and reconnect") { model.saveHostAndReconnect() }
                    }
                } else {
                    Text("No device is configured yet.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Manual local MQTT setup") {
                TextField("Name", text: $model.manualName)
                TextField("Serial", text: $model.manualSerial)
                TextField("Model", text: $model.manualModel)
                TextField("Device type / MQTT root", text: $model.manualType)
                TextField("Hostname or IP (optional)", text: $model.manualHost)
                HStack {
                    TextField("Port", text: $model.manualPort)
                    TextField("MQTT username", text: $model.manualUsername)
                }
                SecureField("MQTT password", text: $model.manualPassword)
                TextField("MQTT root topic", text: $model.manualRootTopic)
                HStack {
                    Button("Save securely and connect") { model.saveManualSetup() }
                    Text("Credentials are stored in Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("macOS") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }
        }
        .formStyle(.grouped)
    }

    private var accountSettings: some View {
        Form {
            Section("MyDyson provisioning") {
                Text("The account is used only to obtain local device credentials. Your password remains in memory for the login request and is not stored by the app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Email", text: $model.accountEmail)
                Picker("MyDyson account country", selection: $model.accountCountry) {
                    ForEach(MyDysonRegion.supported) { region in
                        Text(region.name).tag(region.code)
                    }
                }
                Text("Choose the country selected when this MyDyson account was created, not necessarily where the device is now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("Password", text: $model.accountPassword)
                SecureField("OTP code", text: $model.accountOTP)
                HStack {
                    Button("Send verification code") { model.beginAccountLogin() }
                    Button("Complete login and provision") { model.completeAccountLogin() }
                }
                if let message = model.accountMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Redacted local diagnostics")
                .font(.headline)
            Text("Passwords, tokens, MQTT credentials, and raw payloads are never shown here.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(model.diagnostics.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var about: some View {
        VStack(spacing: 12) {
            Image(systemName: "wind")
                .font(.system(size: 44))
                .foregroundStyle(.cyan)
            Text("Dyson macOS Controller")
                .font(.title2.weight(.semibold))
            Text("Unofficial community project · v0.1.0")
                .foregroundStyle(.secondary)
            Text("Not affiliated with Dyson Ltd. No telemetry or analytics. Normal control stays on your local network after provisioning.")
                .multilineTextAlignment(.center)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
