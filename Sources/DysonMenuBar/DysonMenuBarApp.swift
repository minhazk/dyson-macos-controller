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
final class PopoverPresentation: ObservableObject {
    @Published var isVisible = false
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = AppModel()
    private let presentation = PopoverPresentation()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hostingController: NSViewController?
    private var modelCancellable: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        statusItem.button?.image = PurifierStatusIcon.image
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.imageScaling = .scaleProportionallyDown
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
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        self.popover = popover

        let hostingController = NSHostingController(
            rootView: MenuBarView(model: model, presentation: presentation) { [weak self] height in
                self?.setPopoverHeight(height)
            }
        )
        self.hostingController = hostingController
        popover.contentViewController = hostingController
        hostingController.view.layoutSubtreeIfNeeded()
        setPopoverHeight(hostingController.view.fittingSize.height)
    }

    func popoverWillShow(_ notification: Notification) {
        presentation.isVisible = true
    }

    func popoverDidClose(_ notification: Notification) {
        presentation.isVisible = false
    }

    private func setPopoverHeight(_ height: CGFloat) {
        guard height.isFinite, height > 0 else { return }
        popover?.contentSize = NSSize(width: 360, height: ceil(height))
    }

    private func updateStatusItem(for state: DysonState) {
        guard let button = statusItem?.button else { return }
        let temperature = state.roomTemperatureCelsius.flatMap { $0.isFinite ? $0 : nil }
        button.title = " " + (temperature.map { String(format: "%.0f°", $0.rounded()) } ?? "—°")
        button.toolTip = state.roomTemperatureCelsius.map { String(format: "Dyson Controller • %.1f°C", $0) } ?? "Dyson Controller"
        button.setAccessibilityLabel(temperature.map { String(format: "Dyson fan, room temperature %.1f degrees Celsius", $0) } ?? "Dyson fan, room temperature unavailable")
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
