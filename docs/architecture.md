# Architecture

```text
MenuBarExtra / Settings
          |
       DysonKit
       /      \
  MyDyson API  local MQTT
       |          |
   Keychain   Bonjour/IP fallback
```

## Boundaries

- `Account/` contains the small MyDyson HTTP flow: account status, email challenge, OTP completion, device manifest, and IoT credential retrieval.
- `Provisioning/` contains local credential storage and the upstream-compatible encrypted broker-password decoder.
- `Discovery/` finds `_dyson_mqtt._tcp` services and supports a manually entered hostname/IP fallback.
- `MQTT/` owns one persistent MQTT connection per active device, subscriptions, command publishing, and exponential reconnect backoff.
- `Protocol/` converts Dyson JSON messages into typed state and serializes `STATE-SET` commands.
- `Models/` exposes device metadata, capabilities, and observable state independent of the MQTT implementation.

## Local-first behavior

Provisioning is the only cloud-dependent part. After a device is provisioned, the app uses MQTT on port 1883 on the local network. The cloud access token and local broker credentials are stored in Keychain and are never emitted in logs.

## Protocol notes

The first supported family is the 527 series used by HP04/HP07/HP09 devices. The MQTT root topic is supplied by the device manifest or manual setup; it is not guessed in the transport layer. Capabilities are inferred from model metadata but all controls are still gated by the device capability set.

The implementation intentionally keeps raw-field parsing tolerant: Dyson status values can be scalar strings or two-element `[previous, current]` arrays, and environmental readings can report `OFF`, `INIT`, `FAIL`, or `NONE` instead of numeric values.
