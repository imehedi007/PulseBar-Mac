import Testing
import Foundation
import CoreGraphics
@testable import PulseBar

@MainActor
private final class FakeKeyboardBlocker: KeyboardBlocking {
    var starts = 0
    var stops = 0
    var failure = false
    var onEnd: (() -> Void)?
    var duration: TimeInterval?
    func start(duration: TimeInterval, onEnd: @escaping () -> Void) throws {
        starts += 1
        self.duration = duration
        if failure { throw KeyboardCleaningError.accessibility }
        self.onEnd = onEnd
    }
    func stop() { stops += 1; onEnd = nil }
}

@MainActor
struct KeyboardCleaningTests {
    @Test func legacyPreferencesArePreservedWithoutOverwriting() throws {
        let name = "KeyboardCleaningTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: url)
        }
        var preferences = Preferences()
        preferences.interval = 2
        preferences.cpuEnabled = false
        let data = try JSONEncoder().encode(preferences)
        try PropertyListSerialization.data(fromPropertyList: ["PulseBar.preferences.v1": data],
                                           format: .binary, options: 0).write(to: url)
        SettingsManager.importLegacyPreferences(from: url, into: defaults)
        #expect(SettingsManager(defaults: defaults).preferences == preferences)
        defaults.set(try JSONEncoder().encode(Preferences()), forKey: "PulseBar.preferences.v1")
        SettingsManager.importLegacyPreferences(from: url, into: defaults)
        #expect(SettingsManager(defaults: defaults).preferences == Preferences())
    }

    @Test func durationPersistenceAndBackwardCompatibility() throws {
        let name = "CleaningDurationTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsManager(defaults: defaults)
        #expect(settings.preferences.cleaningDuration == 30)
        for seconds in [15, 30, 60, 120] {
            settings.update { $0.cleaningDuration = seconds }
            #expect(SettingsManager(defaults: defaults).preferences.cleaningDuration == seconds)
        }
        settings.update { $0.cleaningDuration = -1 }
        #expect(settings.preferences.cleaningDuration == 30)
        var legacy = Preferences()
        legacy.interval = 5
        legacy.cpuEnabled = false
        let encoded = try JSONEncoder().encode(legacy)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "cleaningDuration")
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.cleaningDuration == 30)
        #expect(decoded.interval == 5)
        #expect(!decoded.cpuEnabled)
    }

    @Test func selectedDurationAndIndicatorTransitions() {
        let blocker = FakeKeyboardBlocker()
        let cleaning = KeyboardCleaning(blocker: blocker)
        var states: [Bool] = []
        cleaning.onStateChange = {
            states.append(cleaning.isActive)
            #expect((MenuBarFormatter.cleaningIndicator(active: cleaning.isActive) != nil) == cleaning.isActive)
        }
        #expect(MenuBarFormatter.cleaningIndicator(active: false) == nil)
        for seconds in [15, 30, 60, 120] {
            cleaning.setEnabled(true, seconds: seconds)
            #expect(blocker.duration == Double(seconds))
            #expect(cleaning.remainingSeconds == seconds)
            cleaning.setEnabled(true, seconds: 15)
            #expect(blocker.duration == Double(seconds))
            cleaning.stop()
            #expect(cleaning.remainingSeconds == 0)
        }
        #expect(states == [true, false, true, false, true, false, true, false])
        cleaning.onStateChange = nil
    }

    @Test func countdownAndTimeoutIndicator() async throws {
        let blocker = FakeKeyboardBlocker()
        let cleaning = KeyboardCleaning(blocker: blocker, duration: .milliseconds(2200))
        var states: [Bool] = []
        cleaning.onStateChange = { states.append(cleaning.isActive) }
        cleaning.setEnabled(true)
        #expect(cleaning.remainingSeconds == 3)
        for _ in 0..<30 {
            if cleaning.remainingSeconds < 3 { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(cleaning.remainingSeconds < 3)
        for _ in 0..<200 {
            if !cleaning.isActive { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!cleaning.isActive)
        #expect(cleaning.remainingSeconds == 0)
        #expect(MenuBarFormatter.cleaningIndicator(active: cleaning.isActive) == nil)
        #expect(states == [true, false])
        cleaning.onStateChange = nil
    }

    @Test func activationAndDeactivation() {
        let blocker = FakeKeyboardBlocker()
        let cleaning = KeyboardCleaning(blocker: blocker)
        #expect(!cleaning.isActive)
        cleaning.setEnabled(true)
        #expect(cleaning.isActive)
        cleaning.setEnabled(true)
        #expect(blocker.starts == 1)
        cleaning.setEnabled(false)
        #expect(!cleaning.isActive)
        #expect(blocker.stops == 1)
    }

    @Test func permissionFailureLeavesKeyboardEnabled() {
        let blocker = FakeKeyboardBlocker()
        blocker.failure = true
        let cleaning = KeyboardCleaning(blocker: blocker)
        cleaning.setEnabled(true)
        #expect(!cleaning.isActive)
        #expect(cleaning.message != nil)
        #expect(blocker.stops == 1)
    }

    @Test func automaticTimeout() async throws {
        let blocker = FakeKeyboardBlocker()
        let cleaning = KeyboardCleaning(blocker: blocker, duration: .milliseconds(20))
        cleaning.setEnabled(true)
        for _ in 0..<50 {
            if !cleaning.isActive { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!cleaning.isActive)
        #expect(blocker.stops == 1)
    }

    @Test func emergencyExitAndCancelledTimeout() async throws {
        let blocker = FakeKeyboardBlocker()
        let cleaning = KeyboardCleaning(blocker: blocker, duration: .milliseconds(20))
        cleaning.setEnabled(true)
        blocker.onEnd?()
        #expect(!cleaning.isActive)
        try await Task.sleep(for: .milliseconds(60))
        #expect(blocker.stops == 1)
    }

    @Test func keyboardFilterLeavesPointerEventsAlone() {
        #expect(KeyboardEventBlocker.blocks(.keyDown))
        #expect(KeyboardEventBlocker.blocks(.keyUp))
        #expect(KeyboardEventBlocker.blocks(.flagsChanged))
        for type: CGEventType in [.leftMouseDown, .leftMouseUp, .rightMouseDown, .mouseMoved, .scrollWheel] {
            #expect(!KeyboardEventBlocker.blocks(type))
        }
    }
}
