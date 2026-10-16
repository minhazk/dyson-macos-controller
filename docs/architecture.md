# Architecture

```text
NSStatusItem → NSPopover (SwiftUI) / Settings window
          |
       AppModel
          |
       DysonKit
       /      \
  MyDyson API  local MQTT
       |          |
   Keychain   Bonjour/IP fallback
```

## Boundaries

- `Sources/DysonMenuBar/` owns the AppKit status item, content-sized SwiftUI popover, Settings window, and `AppModel`. The status item displays a purifier icon and rounded room temperature.
- `Account/` contains the small MyDyson HTTP flow: account status, email challenge, OTP completion, device manifest, and IoT credential retrieval.
- `Provisioning/` contains local credential storage and the upstream-compatible encrypted broker-password decoder.
- `Discovery/` finds `_dyson_mqtt._tcp` services and supports a manually entered hostname/IP fallback.
- `MQTT/` owns one persistent MQTT connection per active device, subscriptions, command publishing, and exponential reconnect backoff.
- `Protocol/` converts Dyson JSON messages into typed state and serializes `STATE-SET` commands.
- `Models/` exposes device metadata, capabilities, and observable state independent of the MQTT implementation.

## Local-first behavior

Provisioning is the only cloud-dependent part and uses HTTPS. After a device is provisioned, the app uses plaintext MQTT, normally on port 1883, on a trusted local network. The cloud access token and local broker credentials are stored in Keychain and are never emitted in logs. The app persists one active provisioning record; it does not provide multi-device switching.

The transport requests current state and environmental data on connection, sends MQTT keepalive traffic every 10 seconds, and refreshes environmental readings every 30 seconds. Reconnects use exponential backoff. The internal `ComfortHeatingController` is disabled by default and has no exposed UI toggle.

## Presentation and oscillation

The popover measures its content rather than relying on a fixed height. `ControllerStyle` defines the dark monochrome surfaces. `PurifierModelView` renders a noninteractive SceneKit purifier, while SwiftUI owns the oscillation handles and presets. The direction handle shifts both endpoints together, preserves the sweep width, snaps to 5°, and stays within the device's 5–355° limits. Commands are sent when an interaction finishes.

`PurifierAirflowView` is a local visual effect and sends no device commands. It animates only while the popover is visible, the device is connected, and power is on. Reduce Motion pauses the animation. The SceneKit view does not render continuously.

## Build and startup

`./script/build_and_run.sh` is the build-and-launch entry point and the Codex Run action. It selects Xcode, stops the old process, builds and stages `build/DysonMenuBar.app` through `scripts/build-app.sh`, and launches the signed bundle. `--verify` also runs the fixture tests. The bundle uses an explicit ad-hoc signing requirement so its local identity remains stable across rebuilds. Launch at login uses `SMAppService.mainApp` and is configured in Devices settings.

## Protocol notes

The first supported family is the 527 series used by HP04/HP07/HP09 devices. The MQTT root topic is supplied by the device manifest or manual setup; it is not guessed in the transport layer. Capabilities are inferred from model metadata but all controls are still gated by the device capability set.

The implementation intentionally keeps raw-field parsing tolerant: Dyson status values can be scalar strings or two-element `[previous, current]` arrays, and environmental readings can report `OFF`, `INIT`, `FAIL`, or `NONE` instead of numeric values.
