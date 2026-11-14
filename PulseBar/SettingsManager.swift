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
    var memoryThresholds = Thresholds()
    var autoStart = true

    mutating func normalize() {
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
        var value = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        value.normalize()
        preferences = value
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
