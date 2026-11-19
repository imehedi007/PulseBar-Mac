import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let settings = SettingsManager()
    private let cleaning = KeyboardCleaning()
    private let service: MonitoringService
    private let item = NSStatusBar.system.statusItem(withLength: 330)
    private let popover = NSPopover()

    override init() {
        service = MonitoringService(preferences: settings.preferences)
        super.init()
        popover.behavior = .transient
        popover.animates = false
        let hosting = NSHostingController(rootView: StatusPopover(service: service, settings: settings, cleaning: cleaning))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.setAccessibilityIdentifier("PulseBarStatus")
        settings.onChange = { [weak self] preferences in self?.service.configure(preferences) }
        cleaning.onStateChange = { [weak self] in self?.updateTitle() }
        service.onUpdate = { [weak self] in self?.updateTitle() }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(endCleaning), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        settings.refreshLoginStatus()
        service.restart()
    }

    private func updateTitle() {
        let title = MenuBarFormatter.title(snapshot: service.snapshot, preferences: settings.preferences,
                                           running: service.isRunning && !service.isSleeping)
        item.button?.image = MenuBarFormatter.cleaningIndicator(active: cleaning.isActive)
        item.button?.imagePosition = .imageLeading
        item.length = cleaning.isActive ? 354 : 330
        if item.button?.attributedTitle != title { item.button?.attributedTitle = title }
        let cleaningStatus = cleaning.isActive ? ", Keyboard Cleaning active" : ""
        item.button?.toolTip = "PulseBar — " + service.status + cleaningStatus
        item.button?.setAccessibilityLabel("PulseBar, " + title.string + ", " + service.status + cleaningStatus)
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            settings.refreshLoginStatus()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc private func endCleaning() { cleaning.stop() }
    @objc private func willSleep() { cleaning.stop(); service.sleep() }
    @objc private func didWake() { service.wake() }

    func shutdown() {
        cleaning.stop()
        service.stop()
        popover.close()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NSStatusBar.system.removeStatusItem(item)
    }
}
