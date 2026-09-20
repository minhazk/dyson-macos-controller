import AppKit
import Combine
import DysonKit
import SwiftUI

@main
struct DysonMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var modelCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        self.statusItem = statusItem
        updateStatusItem(for: model.state)

        modelCancellable = model.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.updateStatusItem(for: state)
            }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 620)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(model: model)
                .frame(width: 360, height: 620)
        )
        self.popover = popover
    }

    private func updateStatusItem(for state: DysonState) {
        guard let button = statusItem?.button else { return }
        button.title = state.roomTemperatureCelsius.map { String(format: "%.1f°", $0) } ?? "—°"
        button.image = nil
        button.imagePosition = .noImage
        button.toolTip = state.roomTemperatureCelsius.map { String(format: "Dyson Controller • %.1f°C", $0) } ?? "Dyson Controller"
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
