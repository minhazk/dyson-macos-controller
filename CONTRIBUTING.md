# Contributing

Thanks for helping improve Dyson macOS Controller.

## Local development

1. Install Xcode 15 or newer and select it with `xcode-select`.
2. Run `swift test` from the repository root.
3. Build an app bundle with `./scripts/build-app.sh`.
4. Keep credentials, tokens, device IP addresses, and captured MQTT payloads out of commits.

The project uses Swift Package Manager. Keep the app target thin and put reusable protocol, provisioning, discovery, and transport code in `DysonKit`.

## Pull requests

- Add or update fixture-based tests for protocol changes.
- Explain whether a change affects local MQTT, cloud provisioning, or both.
- Do not add Dyson trademarks, logos, or copyrighted assets.
- Redact credentials and personally identifying information from diagnostics.
