import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let settings = SettingsManager()
    private let cleaning = KeyboardCleaning()
    private let clipboard: ClipboardManager
    private let clipboardPanel: ClipboardPanelController
    private let screenshot: ScreenshotManager
    private let service: MonitoringService
    private let item = NSStatusBar.system.statusItem(withLength: 330)
    private let popover = NSPopover()
    private var lastExternalApp: NSRunningApplication?

    override init() {
        service = MonitoringService(preferences: settings.preferences)
        clipboard = ClipboardManager(settings: settings)
        clipboardPanel = ClipboardPanelController(clipboard: clipboard)
        screenshot = ScreenshotManager(settings: settings)
        super.init()
        clipboard.onOpenPanel = { [weak self] targetApp in
            self?.popover.performClose(nil)
            let app = targetApp ?? self?.lastExternalApp
            self?.clipboardPanel.show(targetApp: app)
        }
        popover.behavior = .transient
        popover.animates = false
        popover.appearance = NSAppearance(named: .vibrantDark)
        let hosting = NSHostingController(rootView: StatusPopover(service: service, settings: settings, cleaning: cleaning, clipboard: clipboard, screenshot: screenshot, onDismissPopover: { [weak self] in
            self?.popover.performClose(nil)
        }))
        hosting.sizingOptions = [.preferredContentSize]
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = .clear
        popover.contentViewController = hosting
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.setAccessibilityIdentifier("PulseBarStatus")
        settings.onChange = { [weak self] preferences in
            self?.service.configure(preferences)
            self?.clipboard.pruneToLimit()
            self?.screenshot.setEnabled(preferences.screenshotEnabled)
        }
        cleaning.onStateChange = { [weak self] in self?.updateTitle() }
        service.onUpdate = { [weak self] in self?.updateTitle() }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(endCleaning), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(didActivateApp(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
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
        item.button?.toolTip = "PulseBar \u{2014} " + service.status + cleaningStatus
        item.button?.setAccessibilityLabel("PulseBar, " + title.string + ", " + service.status + cleaningStatus)
    }

    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            settings.refreshLoginStatus()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                window.makeKey()
                window.hasShadow = true
                window.invalidateShadow()
                if let frameView = window.contentView?.superview as? NSVisualEffectView {
                    frameView.material = .hudWindow
                    frameView.state = .active
                    frameView.blendingMode = .behindWindow
                }
            }
        }
    }

    @objc private func didActivateApp(_ notification: Notification) {
        if let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.bundleIdentifier != Bundle.main.bundleIdentifier {
            lastExternalApp = app
        }
    }

    @objc private func endCleaning() { cleaning.stop() }
    @objc private func willSleep() {
        cleaning.stop()
        service.sleep()
        clipboard.sleep()
    }
    @objc private func didWake() {
        service.wake()
        clipboard.wake()
    }

    func shutdown() {
        cleaning.stop()
        service.stop()
        clipboard.shutdown()
        screenshot.shutdown()
        clipboardPanel.close()
        popover.close()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NSStatusBar.system.removeStatusItem(item)
    }
}
