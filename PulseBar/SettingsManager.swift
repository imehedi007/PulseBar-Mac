import Foundation
import Observation
import ServiceManagement

struct Thresholds: Codable, Equatable, Sendable {
    var warning = 75
    var critical = 90

    mutating func normalize() {
        warning = min(99, max(1, warning))
        critical = min(100, max(warning + 1, critical))
    }
}

struct Preferences: Codable, Equatable, Sendable {
    var cpuEnabled = true
    var memoryEnabled = true
    var networkEnabled = true
    var interval: Double = 0.5
    var cpuThresholds = Thresholds()
    // Retained only for compatibility with saved preferences; RAM colors use OS pressure.
    var memoryThresholds = Thresholds()
    var autoStart = true
    var cleaningDuration = 30
    var clipboardHistoryEnabled = true
    var clipboardLimit = 50
    var screenshotEnabled = true
    var screenshotAutoSave = false
    var screenshotSaveDirectory = "~/Screenshots"
    var screenshotTouchBarEnabled = false
    var screenshotNativeTouchBarInterceptEnabled = true

    init() {}

    private enum CodingKeys: String, CodingKey {
        case cpuEnabled, memoryEnabled, networkEnabled, interval
        case cpuThresholds, memoryThresholds, autoStart, cleaningDuration
        case clipboardHistoryEnabled, clipboardLimit
        case screenshotEnabled, screenshotAutoSave, screenshotSaveDirectory, screenshotTouchBarEnabled, screenshotNativeTouchBarInterceptEnabled
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        cpuEnabled = try values.decode(Bool.self, forKey: .cpuEnabled)
        memoryEnabled = try values.decode(Bool.self, forKey: .memoryEnabled)
        networkEnabled = try values.decode(Bool.self, forKey: .networkEnabled)
        interval = try values.decode(Double.self, forKey: .interval)
        cpuThresholds = try values.decode(Thresholds.self, forKey: .cpuThresholds)
        memoryThresholds = try values.decode(Thresholds.self, forKey: .memoryThresholds)
        autoStart = try values.decode(Bool.self, forKey: .autoStart)
        cleaningDuration = try values.decodeIfPresent(Int.self, forKey: .cleaningDuration) ?? 30
        clipboardHistoryEnabled = try values.decodeIfPresent(Bool.self, forKey: .clipboardHistoryEnabled) ?? true
        clipboardLimit = try values.decodeIfPresent(Int.self, forKey: .clipboardLimit) ?? 50
        screenshotEnabled = try values.decodeIfPresent(Bool.self, forKey: .screenshotEnabled) ?? true
        screenshotAutoSave = try values.decodeIfPresent(Bool.self, forKey: .screenshotAutoSave) ?? false
        screenshotSaveDirectory = try values.decodeIfPresent(String.self, forKey: .screenshotSaveDirectory) ?? "~/Screenshots"
        screenshotTouchBarEnabled = try values.decodeIfPresent(Bool.self, forKey: .screenshotTouchBarEnabled) ?? false
        screenshotNativeTouchBarInterceptEnabled = try values.decodeIfPresent(Bool.self, forKey: .screenshotNativeTouchBarInterceptEnabled) ?? true
    }

    mutating func normalize() {
        if screenshotSaveDirectory == "~/Pictures/Screenshots" {
            screenshotSaveDirectory = "~/Screenshots"
        }
        if ![15, 30, 60, 120].contains(cleaningDuration) { cleaningDuration = 30 }
        if ![25, 50, 100, 200].contains(clipboardLimit) { clipboardLimit = 50 }
        if ![0.5, 1, 2, 5].contains(interval) { interval = 0.5 }
        cpuThresholds.normalize()
        memoryThresholds.normalize()
    }
}

@MainActor @Observable
final class SettingsManager {
    private(set) var preferences: Preferences
    private(set) var loginEnabled = false
    private(set) var loginNeedsApproval = false
    private(set) var loginError: String?
    private(set) var loginBusy = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onChange: ((Preferences) -> Void)?
    private static let key = "PulseBar.preferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Direct-distribution builds retain preferences from the former sandbox.
        if defaults === UserDefaults.standard, defaults.data(forKey: Self.key) == nil,
           let identifier = Bundle.main.bundleIdentifier {
            let legacy = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Containers/\(identifier)/Data/Library/Preferences/\(identifier).plist")
            Self.importLegacyPreferences(from: legacy, into: defaults)
        }
        var value = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        value.normalize()
        preferences = value
    }

    static func importLegacyPreferences(from url: URL, into defaults: UserDefaults) {
        guard defaults.data(forKey: key) == nil,
              let contents = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: contents, format: nil) as? [String: Any],
              let data = plist[key] as? Data,
              (try? JSONDecoder().decode(Preferences.self, from: data)) != nil else { return }
        defaults.set(data, forKey: key)
    }

    func update(_ change: (inout Preferences) -> Void) {
        var value = preferences
        change(&value)
        value.normalize()
        guard value != preferences else { return }
        preferences = value
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.key) }
        onChange?(value)
    }

    func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        loginNeedsApproval = status == .requiresApproval
    }

    func setLoginEnabled(_ enabled: Bool) {
        guard !loginBusy else { return }
        loginBusy = true
        loginError = nil
        Task { @MainActor in
            defer { loginBusy = false; refreshLoginStatus() }
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try await SMAppService.mainApp.unregister() }
            } catch {
                loginError = error.localizedDescription
            }
        }
    }

    func restoreDefaults() {
        update { $0 = Preferences() }
        if loginEnabled { setLoginEnabled(false) }
    }
}
