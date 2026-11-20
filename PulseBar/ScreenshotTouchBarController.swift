import Foundation
import AppKit

/// Manages Touch Bar screenshot integration for PulseBar.
///
/// Supports two complementary approaches:
/// 1. **Native Control Strip Interception (Primary)**:
///    Allows users to drag macOS's native Screenshot camera button anywhere in the Touch Bar Control Strip
///    (such as the far right edge via System Settings > Keyboard > Touch Bar Settings > Customize Control Strip).
///    When tapped, PulseBar intercepts the system screenshot launcher, closes the native utility,
///    and opens PulseBar's Lightshot-style annotation tool.
/// 2. **Custom System Tray Item**:
///    Injects an optional custom camera button into the Control Strip via DFRFoundation.
@MainActor
final class ScreenshotTouchBarController: NSObject {
    static let itemIdentifier = NSTouchBarItem.Identifier("com.pulsebar.controlstrip.screenshot")

    var onTrigger: (() -> Void)?
    private var touchBarItem: NSCustomTouchBarItem?
    private(set) var isControlStripPresent = false
    private(set) var isInterceptingNative = false

    private var interceptTimer: Timer?
    private var lastInterceptTime: Date = .distantPast

    private typealias DFRElementSetControlStripPresenceForIdentifierFunc = @convention(c) (CFString, Bool) -> Void

    private lazy var setPresenceFunc: DFRElementSetControlStripPresenceForIdentifierFunc? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW) else {
            return nil
        }
        guard let sym = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") else {
            return nil
        }
        return unsafeBitCast(sym, to: DFRElementSetControlStripPresenceForIdentifierFunc.self)
    }()

    /// Indicates whether the host macOS system has DFR (Digital Function Row / Touch Bar) support.
    var isTouchBarSupported: Bool {
        setPresenceFunc != nil && NSClassFromString("NSTouchBarItem") != nil
    }

    // MARK: - Native Touch Bar Screenshot Interception
    func setNativeInterception(_ enabled: Bool) {
        guard enabled != isInterceptingNative else { return }
        isInterceptingNative = enabled

        if enabled {
            startNativeInterceptTimer()
        } else {
            stopNativeInterceptTimer()
        }
    }

    private func startNativeInterceptTimer() {
        stopNativeInterceptTimer()
        interceptTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.checkForNativeScreenshotLaunch()
        }
    }

    private func stopNativeInterceptTimer() {
        interceptTimer?.invalidate()
        interceptTimer = nil
    }

    private func checkForNativeScreenshotLaunch() {
        guard Date().timeIntervalSince(lastInterceptTime) > 1.0 else { return }

        // O(1) LaunchServices indexed lookup by bundle identifier instead of iterating all running apps.
        // Note: screencaptureui has LSUIElement = 1, so NSWorkspace.didLaunchApplicationNotification
        // does NOT post for it; direct LaunchServices lookup is required and consumes negligible CPU.
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.screencaptureui").first else {
            return
        }

        lastInterceptTime = Date()

        // Instantly terminate native screencaptureui
        kill(app.processIdentifier, SIGKILL)

        // Terminate parent screencapture process
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-9", "-x", "screencapture"]
        try? pkill.run()

        // Launch PulseBar screenshot capture
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.onTrigger?()
        }
    }

    // MARK: - Custom Control Strip Presence
    func setControlStripPresence(_ present: Bool) {
        guard let setPresence = setPresenceFunc else { return }
        if present {
            registerItemIfNeeded()
            setPresence(Self.itemIdentifier.rawValue as CFString, true)
            isControlStripPresent = true
        } else {
            if isControlStripPresent {
                setPresence(Self.itemIdentifier.rawValue as CFString, false)
                isControlStripPresent = false
            }
        }
    }

    private func registerItemIfNeeded() {
        guard touchBarItem == nil else { return }

        let item = NSCustomTouchBarItem(identifier: Self.itemIdentifier)
        let image = NSImage(systemSymbolName: "camera.fill", accessibilityDescription: "Take Screenshot") ?? NSImage()
        let button = NSButton(image: image, target: self, action: #selector(handleButtonTap))
        item.view = button
        item.customizationLabel = "Screenshot"
        self.touchBarItem = item

        guard let itemClass = NSClassFromString("NSTouchBarItem") as AnyObject? else { return }
        let sel = NSSelectorFromString("addSystemTrayItem:")
        if itemClass.responds(to: sel) {
            _ = itemClass.perform(sel, with: item)
        }
    }

    @objc private func handleButtonTap() {
        onTrigger?()
    }

    /// Unregisters the Control Strip presence and stops native interception during app termination or feature deactivation.
    func tearDown() {
        setControlStripPresence(false)
        setNativeInterception(false)
        touchBarItem = nil
    }

    deinit {
        interceptTimer?.invalidate()
    }
}
