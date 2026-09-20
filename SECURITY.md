# Security policy

Please do not publish Dyson account credentials, access tokens, MQTT passwords, serial numbers, or raw device payloads in issues or pull requests.

Report suspected security issues privately to the repository maintainers rather than opening a public issue. This project has no telemetry and does not operate a central service.

The app stores credentials in the macOS Keychain. Diagnostic logs intentionally redact secrets. Normal device commands use the local LAN after provisioning; cloud access is used only for the optional MyDyson provisioning flow.
