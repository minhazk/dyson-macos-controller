import Foundation

public final class BonjourDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    public static let shared = BonjourDiscovery()

    public static func fallbackHostname(for serial: String) -> String? {
        let cleaned = serial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        let identifier = cleaned.split(separator: "_", maxSplits: 1).last.map(String.init) ?? cleaned
        return "\(identifier).local"
    }

    private let lock = NSLock()
    private var browser: NetServiceBrowser?
    private var pending: CheckedContinuation<String?, Never>?
    private var serial = ""

    public func discover(serial: String, timeout: TimeInterval = 5) async -> String? {
        await withCheckedContinuation { continuation in
            lock.lock()
            pending = continuation
            self.serial = serial.uppercased()
            let browser = NetServiceBrowser()
            self.browser = browser
            lock.unlock()

            browser.delegate = self
            DispatchQueue.main.async {
                browser.schedule(in: .main, forMode: .default)
                browser.searchForServices(ofType: "_dyson_mqtt._tcp.", inDomain: "local.")
            }

            Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self?.finish(nil)
            }
        }
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        service.delegate = self
        service.schedule(in: .main, forMode: .default)
        service.resolve(withTimeout: 2)
    }

    public func netServiceDidResolveAddress(_ sender: NetService) {
        lock.lock()
        let expectedSerial = serial
        lock.unlock()

        let haystack = "\(sender.name) \(sender.hostName ?? "")".uppercased()
        guard haystack.contains(expectedSerial) else { return }
        finish(sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")))
    }

    public func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        finish(nil)
    }

    public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {}

    private func finish(_ host: String?) {
        lock.lock()
        guard let continuation = pending else {
            lock.unlock()
            return
        }
        pending = nil
        let browser = self.browser
        self.browser = nil
        lock.unlock()

        DispatchQueue.main.async {
            browser?.stop()
            browser?.remove(from: .main, forMode: .default)
        }
        continuation.resume(returning: host)
    }
}
