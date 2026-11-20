import Foundation
import AppKit
import Testing
@testable import PulseBar

struct PulseBarTests {
    @Test func cpuDeltasAndFirstSample() {
        let first = CPUTicks(user: 10, system: 20, idle: 60, nice: 10)
        let next = CPUTicks(user: 20, system: 40, idle: 120, nice: 20)
        #expect(CPUTicks.utilization(previous: nil, current: first) == nil)
        #expect(CPUTicks.utilization(previous: first, current: next) == 40)
        #expect(CPUTicks.utilization(previous: next, current: first) == nil)
        #expect(CPUTicks.utilization(previous: first, current: first) == 0)
    }

    @Test func memoryCalculation() {
        let memory = MemoryReading.calculate(total: 1000, pageSize: 10, active: 20,
                                              inactive: 10, wired: 20, compressed: 10, purgeable: 5)
        #expect(memory.used == 550)
        #expect(memory.available == 450)
        #expect(abs(memory.percentage - 55) < 0.0001)
        #expect(MemoryReading.calculate(total: 100, pageSize: 10, active: 100,
                                        inactive: 0, wired: 0, compressed: 0, purgeable: 0).used == 100)
        #expect(MemoryReading.calculate(total: 0, pageSize: 10, active: 0,
                                        inactive: 0, wired: 0, compressed: 0, purgeable: 9).percentage == 0)
    }

    @Test func activityMonitorAlignedMemoryCalculation() {
        // App = (internal 25 - purgeable 5) = 20 pages
        // Wired = 20 pages
        // Compressed = 10 pages
        // Used = (20 + 20 + 10) * 10 = 500 bytes (inactive 10 pages excluded)
        let memory = MemoryReading.calculate(total: 1000, pageSize: 10, active: 20,
                                              inactive: 10, wired: 20, compressed: 10,
                                              purgeable: 5, internalPages: 25)
        #expect(memory.used == 500)
        #expect(memory.available == 500)
        #expect(abs(memory.percentage - 50) < 0.0001)
        #expect(abs((memory.estimatedHeadroomPercentage ?? 0) - 50) < 0.0001)
    }

    @Test func memoryPressureCurrent() {
        let pressure = MemoryPressure.current()
        #expect([.normal, .warning, .critical].contains(pressure))
    }

    @Test func networkDeltasAndResets() {
        var calculator = NetworkCalculator()
        func bytes(_ received: UInt64, _ sent: UInt64, _ index: UInt32 = 1) -> InterfaceBytes {
            InterfaceBytes(received: received, sent: sent, index: index)
        }
        #expect(calculator.sample(["en0": bytes(100, 200)], time: 1) == nil)
        #expect(calculator.sample(["en0": bytes(600, 1200)], time: 1.5) == NetworkRate(download: 1000, upload: 2000))
        #expect(calculator.sample(["en0": bytes(600, 1200)], time: 2) == NetworkRate())
        #expect(calculator.sample(["en0": bytes(1, 2)], time: 3) == NetworkRate())
        #expect(calculator.sample(["en1": bytes(90000, 90000)], time: 4) == NetworkRate())
        #expect(calculator.sample(["en1": bytes(90001, 90001, 2)], time: 5) == NetworkRate())
        #expect(calculator.sample([:], time: 5) == nil)
        #expect(calculator.sample([:], time: 6) == NetworkRate())
    }

    @Test func multipleInterfacesAndDirectionReset() {
        var calculator = NetworkCalculator()
        _ = calculator.sample(["en0": .init(received: 100, sent: 100, index: 1),
                               "en1": .init(received: 100, sent: 100, index: 2)], time: 1)
        let value = calculator.sample(["en0": .init(received: 0, sent: 200, index: 1),
                                       "en1": .init(received: 200, sent: 200, index: 2)], time: 2)
        #expect(value == NetworkRate(download: 100, upload: 200))
    }

    @Test func units() {
        #expect(MenuBarFormatter.speed(nil) == "—")
        #expect(MenuBarFormatter.speed(0) == "0 bps")
        #expect(MenuBarFormatter.speed(1) == "8 bps")
        #expect(MenuBarFormatter.speed(124) == "992 bps")
        #expect(MenuBarFormatter.speed(125) == "1.0 Kbps")
        #expect(MenuBarFormatter.speed(512) == "4.1 Kbps")
        #expect(MenuBarFormatter.speed(1000) == "8.0 Kbps")
        #expect(MenuBarFormatter.speed(125_000) == "1.0 Mbps")
        #expect(MenuBarFormatter.speed(1_000_000) == "8.0 Mbps")
        #expect(MenuBarFormatter.speed(5_000_000) == "40.0 Mbps")
        #expect(MenuBarFormatter.speed(10_000_000) == "80.0 Mbps")
        #expect(MenuBarFormatter.speed(12_400_000) == "99.2 Mbps")
        #expect(MenuBarFormatter.speed(125_000_000) == "1.0 Gbps")
        #expect(MenuBarFormatter.speed(1_000_000_000) == "8.0 Gbps")
        #expect(MenuBarFormatter.speed(-1) == "—")
        #expect(MenuBarFormatter.speed(.nan) == "—")
        #expect(MenuBarFormatter.speed(.infinity) == "—")
        #expect(MenuBarFormatter.speed(.greatestFiniteMagnitude) == "—")
        #expect(MenuBarFormatter.percent(90) == "90%")
        #expect(MenuBarFormatter.gigabytes(8_589_934_592) == "8.0")
        #expect(MenuBarFormatter.gigabytes(17_179_869_184) == "16.0")
    }

    @Test func thresholds() {
        let thresholds = Thresholds()
        #expect(MetricLevel.level(74.99, thresholds: thresholds) == .normal)
        #expect(MetricLevel.level(75, thresholds: thresholds) == .warning)
        #expect(MetricLevel.level(89.99, thresholds: thresholds) == .warning)
        #expect(MetricLevel.level(90, thresholds: thresholds) == .critical)
        #expect(MetricLevel.level(100, thresholds: thresholds) == .critical)
        #expect(MetricLevel.level(80, thresholds: Thresholds(warning: 50, critical: 80)) == .critical)
    }

    @MainActor @Test func independentColors() throws {
        let title = MenuBarFormatter.title(snapshot: .init(cpu: 95, memory: .init(total: 100, used: 20)),
                                            preferences: Preferences(), running: true)
        let cpuRange = (title.string as NSString).range(of: "CPU")
        let ramRange = (title.string as NSString).range(of: "RAM")
        let cpu = try #require(title.attribute(.foregroundColor, at: cpuRange.location, effectiveRange: nil) as? NSColor)
        let ram = try #require(title.attribute(.foregroundColor, at: ramRange.location, effectiveRange: nil) as? NSColor)
        #expect(cpu == NSColor.systemRed)
        #expect(cpu != ram)
    }

    @MainActor @Test func titleWithDisabledMetrics() {
        var preferences = Preferences()
        preferences.cpuEnabled = false
        preferences.memoryEnabled = false
        preferences.networkEnabled = false
        let title = MenuBarFormatter.title(snapshot: MonitoringSnapshot(), preferences: preferences, running: true)
        #expect(title.string == "↓ off ↑ off | CPU off | RAM off")
    }

    @Test func thresholdNormalizationBounds() {
        var t = Thresholds(warning: 100, critical: 10)
        t.normalize()
        #expect(t.warning == 99)
        #expect(t.critical == 100)

        var t2 = Thresholds(warning: -5, critical: -10)
        t2.normalize()
        #expect(t2.warning == 1)
        #expect(t2.critical == 2)
    }

    @MainActor @Test func settingsPersistenceAndValidation() throws {
        let name = "PulseBarTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = SettingsManager(defaults: defaults)
        #expect(settings.preferences == Preferences())
        settings.update {
            $0.interval = 2
            $0.cpuEnabled = false
            $0.autoStart = false
            $0.cpuThresholds = Thresholds(warning: 60, critical: 85)
        }
        let restored = SettingsManager(defaults: defaults)
        #expect(restored.preferences == settings.preferences)
        restored.update {
            $0.interval = -1
            $0.memoryThresholds = Thresholds(warning: 200, critical: -1)
        }
        #expect(restored.preferences.interval == 0.5)
        #expect(restored.preferences.memoryThresholds == Thresholds(warning: 99, critical: 100))
        restored.restoreDefaults()
        #expect(SettingsManager(defaults: defaults).preferences == Preferences())
    }

    @MainActor @Test func monitoringLifecycle() async throws {
        var preferences = Preferences()
        preferences.interval = 0.5
        let service = MonitoringService(preferences: preferences)
        service.restart()
        try await Task.sleep(for: .seconds(1.2))
        #expect(service.isRunning)
        #expect(service.snapshot.memory != nil)
        service.toggle()
        #expect(!service.isRunning)
        #expect(service.status == "Paused")
        try await Task.sleep(for: .milliseconds(600))
        #expect(service.snapshot == MonitoringSnapshot())
        service.toggle()
        #expect(service.isRunning)
        service.sleep()
        #expect(service.status == "Sleeping")
        service.wake()
        #expect(!service.isSleeping)
        service.stop()
    }

    @Test func memoryPressureEvents() {
        #expect(MemoryPressure(events: []) == .unknown)
        #expect(MemoryPressure(events: .normal) == .normal)
        #expect(MemoryPressure(events: .warning) == .warning)
        #expect(MemoryPressure(events: .critical) == .critical)
        #expect(MemoryPressure(events: [.normal, .warning]) == .warning)
        #expect(MemoryPressure(events: [.normal, .warning, .critical]) == .critical)
        #expect(MonitoringSnapshot().memoryPressure == .unknown)
    }

    @MainActor @Test func memoryPressureColorTransitions() throws {
        let states: [MemoryPressure] = [.unknown, .normal, .warning, .critical, .warning, .normal]
        for state in states {
            for used: UInt64 in [60, 92] {
                var preferences = Preferences()
                // Legacy RAM thresholds must have no influence on pressure colors.
                preferences.memoryThresholds = Thresholds(warning: 1, critical: 2)
                let snapshot = MonitoringSnapshot(cpu: 95, memory: .init(total: 100, used: used),
                                                  memoryPressure: state)
                let title = MenuBarFormatter.title(snapshot: snapshot, preferences: preferences, running: true)
                let ramRange = (title.string as NSString).range(of: "RAM")
                let cpuRange = (title.string as NSString).range(of: "CPU")
                let ram = try #require(title.attribute(.foregroundColor, at: ramRange.location, effectiveRange: nil) as? NSColor)
                let cpu = try #require(title.attribute(.foregroundColor, at: cpuRange.location, effectiveRange: nil) as? NSColor)
                let expected: NSColor
                switch state {
                case .unknown: expected = .systemGray
                case .normal: expected = MetricLevel.normal.color
                case .warning: expected = .systemYellow
                case .critical: expected = .systemRed
                }
                for name in [NSAppearance.Name.aqua, .darkAqua] {
                    let appearance = try #require(NSAppearance(named: name))
                    appearance.performAsCurrentDrawingAppearance {
                        #expect(ram.usingColorSpace(.deviceRGB) == expected.usingColorSpace(.deviceRGB))
                    }
                }
                #expect(cpu == .systemRed)
                #expect(title.string.contains("RAM \(used)%"))
            }
        }
    }

    @MainActor @Test func inactiveMemoryPressureIsGrey() throws {
        var preferences = Preferences()
        let snapshot = MonitoringSnapshot(memory: .init(total: 100, used: 92), memoryPressure: .critical)
        for running in [true, false] {
            preferences.memoryEnabled = !running
            let title = MenuBarFormatter.title(snapshot: snapshot, preferences: preferences, running: running)
            let range = (title.string as NSString).range(of: "RAM")
            let color = try #require(title.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor)
            #expect(color == .systemGray)
        }
    }

    @MainActor @Test func memoryPressureLifecycle() async throws {
        var preferences = Preferences()
        let service = MonitoringService(preferences: preferences)
        #expect(service.snapshot.memoryPressure == .unknown)
        service.restart()
        #expect(service.snapshot.memoryPressure == .unknown)
        service.sleep()
        try await Task.sleep(for: .milliseconds(100))
        #expect(service.snapshot.memoryPressure == .unknown)
        service.wake()
        #expect(service.snapshot.memoryPressure == .unknown)
        preferences.memoryEnabled = false
        service.configure(preferences)
        try await Task.sleep(for: .milliseconds(600))
        #expect(service.snapshot.memoryPressure == .unknown)
        #expect(service.snapshot.memory == nil)
        preferences.memoryEnabled = true
        service.configure(preferences)
        #expect(service.snapshot.memoryPressure == .unknown)
        service.toggle()
        try await Task.sleep(for: .milliseconds(100))
        #expect(service.snapshot.memoryPressure == .unknown)
        service.toggle()
        #expect(service.snapshot.memoryPressure == .unknown)
        service.stop()
        try await Task.sleep(for: .milliseconds(100))
        #expect(service.snapshot == MonitoringSnapshot())
    }

    @Test func estimatedHeadroomInitialStateAndTransitions() {
        var snapshot = MonitoringSnapshot()
        #expect(snapshot.memoryPressure == .unknown)
        #expect(snapshot.memory?.estimatedHeadroomPercentage == nil)
        snapshot.memory = .calculate(total: 1000, pageSize: 10, active: 42,
                                    inactive: 20, wired: 20, compressed: 10, purgeable: 0)
        #expect(snapshot.memory?.percentage == 92)
        #expect(snapshot.memory?.estimatedHeadroomPercentage == 8)
        #expect(snapshot.memoryPressure == .unknown)
        for event: DispatchSource.MemoryPressureEvent in [.normal, .warning, .critical, .normal] {
            snapshot.memoryPressure = MemoryPressure(events: event)
            #expect(snapshot.memory?.estimatedHeadroomPercentage == 8)
            #expect(snapshot.memoryPressure == MemoryPressure(events: event))
        }
        snapshot = MonitoringSnapshot()
        #expect(snapshot.memory?.estimatedHeadroomPercentage == nil)
        #expect(snapshot.memoryPressure == .unknown)
    }

    @Test func estimatedHeadroomBounds() {
        #expect(MemoryReading(total: 0, used: 0).estimatedHeadroomPercentage == nil)
        #expect(MemoryReading(total: 100, used: 0).estimatedHeadroomPercentage == 100)
        #expect(MemoryReading(total: 100, used: 100).estimatedHeadroomPercentage == 0)
        #expect(MemoryReading(total: 100, used: 60).estimatedHeadroomPercentage == 40)
    }

    @Test func nativeMemorySample() throws {
        let memory = try #require(MemoryMonitor().sample())
        #expect(memory.total > 0)
        #expect(memory.used <= memory.total)
    }
}
