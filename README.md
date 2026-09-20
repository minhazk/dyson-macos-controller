# Dyson macOS Controller

Unofficial native macOS menu-bar controller for compatible Dyson air-treatment devices.

> This is an independent community project. It is not affiliated with, endorsed by, or sponsored by Dyson Ltd. Do not use Dyson logos or copyrighted assets with this project.

## Status

The initial tested target is the Dyson Purifier Hot+Cool Formaldehyde HP09 (`527K`). The repository contains a functioning fixture-tested MVP core, a native `MenuBarExtra` shell, local MQTT transport, Bonjour discovery, Keychain storage, and MyDyson email/OTP provisioning. Live device verification still requires a physical compatible device and the user's own MyDyson account/OTP.

## Supported functionality

- Power and fan speed 1–10.
- Auto mode, heating, target temperature, oscillation, custom oscillation angles, airflow direction, and night mode.
- Room temperature, humidity, PM2.5, PM10, VOC index, and NO₂ index when reported by the device.
- Local MQTT state subscriptions with a single connection per active device.
- Bonjour discovery with hostname/IP manual fallback.
- Optional MyDyson email/password/OTP provisioning.
- Keychain-only credential storage and redacted diagnostic logging.

Controls are capability-gated so additional compatible models can be added without hardcoding the UI to HP09.

## Privacy model

There is no telemetry or analytics. Cloud services are used only by the optional initial provisioning flow. Normal control stays on the local LAN. Passwords, access tokens, and MQTT credentials are not stored in plaintext or written to logs.

## Build

Requires macOS 13 or newer, Xcode 15 or newer, and Swift Package Manager.

```bash
swift test
./scripts/build-app.sh
open build/DysonMenuBar.app
```

The script creates an ad-hoc signed app bundle for local development. Release signing, notarization, and launch-at-login registration are intentionally left to the user's developer identity and release workflow.

## Known limitations

- Dyson's private API may change; provisioning errors should be handled through the manual setup flow.
- A live Dyson device is not available in CI, so CI uses only synthetic MQTT fixtures.
- Heating and custom oscillation controls are hidden or disabled when the manifest does not advertise the required capability.
- The app currently focuses on one active device in the menu bar; the settings model is ready for multiple stored devices.

## Acknowledgements

Protocol behavior is informed by the community work in [opendyson](https://github.com/libdyson-wg/opendyson), [libdyson-neon](https://github.com/libdyson-wg/libdyson-neon), [appapi](https://github.com/libdyson-wg/appapi), and [ha-dyson](https://github.com/libdyson-wg/ha-dyson). The local transport implements the Dyson-compatible MQTT 3.1 wire protocol directly.
