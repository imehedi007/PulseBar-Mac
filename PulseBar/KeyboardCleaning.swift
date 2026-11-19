import AppKit
import ApplicationServices
import Carbon
import Observation

@MainActor
protocol KeyboardBlocking: AnyObject {
    func start(duration: TimeInterval, onEnd: @escaping () -> Void) throws
    func stop()
}

enum KeyboardCleaningError: LocalizedError {
    case accessibility, unavailable
    var errorDescription: String? {
        switch self {
        case .accessibility:
            return "Allow PulseBar in System Settings → Privacy & Security → Accessibility, then try again. Keyboard input remains enabled."
        case .unavailable:
            return "macOS could not block keyboard input. Check Accessibility and Input Monitoring permissions, then restart PulseBar and try again."
        }
    }
}

/// A session-only controller. Tests inject a blocker so they never intercept real input.
@MainActor @Observable
final class KeyboardCleaning {
    private(set) var isActive = false
    private(set) var message: String?
    @ObservationIgnored private let blocker: KeyboardBlocking
    @ObservationIgnored private var timeout: Task<Void, Never>?
    private(set) var remainingSeconds = 0
    @ObservationIgnored var onStateChange: (() -> Void)?
    @ObservationIgnored private let testDuration: Duration?

    init(blocker: KeyboardBlocking? = nil, duration: Duration? = nil) {
        self.blocker = blocker ?? KeyboardEventBlocker()
        self.testDuration = duration
    }

    func setEnabled(_ enabled: Bool, seconds: Int = 30) {
        guard enabled else { stop(); return }
        guard !isActive else { return }
        message = nil
        let seconds = [15, 30, 60, 120].contains(seconds) ? seconds : 30
        let duration = testDuration ?? .seconds(seconds)
        let components = duration.components
        let interval = Double(components.seconds) + Double(components.attoseconds) / 1e18
        do {
            try blocker.start(duration: interval) { [weak self] in self?.stop() }
            let deadline = ContinuousClock.now.advanced(by: duration)
            remainingSeconds = Int(ceil(interval))
            isActive = true
            onStateChange?()
            // Sleep to an absolute deadline: delayed UI updates never extend cleaning.
            timeout = Task { [weak self] in
                while !Task.isCancelled {
                    let next = min(deadline, ContinuousClock.now.advanced(by: .seconds(1)))
                    do { try await Task.sleep(until: next, clock: .continuous) } catch { return }
                    guard let self else { return }
                    let remaining = ContinuousClock.now.duration(to: deadline).components
                    remainingSeconds = max(0, Int(ceil(Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18)))
                    if ContinuousClock.now >= deadline { stop(); return }
                }
            }
        } catch {
            blocker.stop()
            message = error.localizedDescription
        }
    }

    func stop() {
        timeout?.cancel()
        timeout = nil
        blocker.stop()
        let wasActive = isActive
        isActive = false
        remainingSeconds = 0
        if wasActive { onStateChange?() }
    }

    func openPermissions() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Main-run-loop event tap; no keyboard contents are retained, logged or transmitted.
@MainActor
final class KeyboardEventBlocker: KeyboardBlocking {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var onEnd: (() -> Void)?
    private var deadline: TimeInterval = 0

    static func blocks(_ type: CGEventType) -> Bool {
        type == .keyDown || type == .keyUp || type == .flagsChanged
            || type.rawValue == UInt32(NSEvent.EventType.systemDefined.rawValue)
    }

    func start(duration: TimeInterval, onEnd: @escaping () -> Void) throws {
        stop()
        guard AXIsProcessTrusted() else {
            throw KeyboardCleaningError.accessibility
        }
        // Secure input bypasses ordinary event taps. Do not claim protection there.
        guard !IsSecureEventInputEnabled() else { throw KeyboardCleaningError.unavailable }
        let types: [UInt32] = [CGEventType.keyDown.rawValue, CGEventType.keyUp.rawValue,
                              CGEventType.flagsChanged.rawValue, UInt32(NSEvent.EventType.systemDefined.rawValue)]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask,
                                         callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<KeyboardEventBlocker>.fromOpaque(context).takeUnretainedValue()
                return owner.handle(type, event: event)
            }
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            throw KeyboardCleaningError.unavailable
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw KeyboardCleaningError.unavailable
        }
        self.tap = tap
        self.source = source
        self.onEnd = onEnd
        deadline = ProcessInfo.processInfo.systemUptime + duration
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            stop()
            throw KeyboardCleaningError.unavailable
        }
    }

    private func handle(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput
            || ProcessInfo.processInfo.systemUptime >= deadline || IsSecureEventInputEnabled() {
            let completion = onEnd
            stop()
            completion?()
            return Unmanaged.passUnretained(event)
        }
        // Escape is an emergency exit even if the popover is closed.
        if type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 53 {
            let completion = onEnd
            stop()
            completion?()
            return nil
        }
        return Self.blocks(type) ? nil : Unmanaged.passUnretained(event)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        onEnd = nil
    }

    deinit {
        // Invalidating the port removes the filter even if the owner disappears.
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
}
