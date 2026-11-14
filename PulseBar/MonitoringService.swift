import Foundation
import Observation

struct MonitoringSnapshot: Equatable, Sendable {
    var cpu: Double?
    var memory: MemoryReading?
    var network: NetworkRate?
}

// Mutable monitor state is confined to this serial queue. No UI objects cross it.
private final class SamplingWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.pulsebar.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var cpu = CPUMonitor()
    private var network = NetworkMonitor()
    private let memory = MemoryMonitor()

    func configure(_ preferences: Preferences, running: Bool,
                   deliver: @escaping @Sendable (MonitoringSnapshot) -> Void) {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            cpu = CPUMonitor()
            network = NetworkMonitor()
            guard running && (preferences.cpuEnabled || preferences.memoryEnabled || preferences.networkEnabled) else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: preferences.interval, leeway: .milliseconds(25))
            source.setEventHandler { [weak self] in
                guard let self else { return }
                let snapshot = MonitoringSnapshot(
                    cpu: preferences.cpuEnabled ? cpu.sample() : nil,
                    memory: preferences.memoryEnabled ? memory.sample() : nil,
                    network: preferences.networkEnabled ? network.sample() : nil)
                deliver(snapshot)
            }
            timer = source
            source.resume()
        }
    }

    deinit { timer?.cancel() }
}

@MainActor @Observable
final class MonitoringService {
    private(set) var snapshot = MonitoringSnapshot()
    private(set) var isRunning: Bool
    private(set) var isSleeping = false
    @ObservationIgnored private let worker = SamplingWorker()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored var onUpdate: (() -> Void)?
    private var preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
        isRunning = preferences.autoStart
    }

    var status: String {
        if !isRunning { return "Paused" }
        if isSleeping { return "Sleeping" }
        if !preferences.cpuEnabled && !preferences.memoryEnabled && !preferences.networkEnabled {
            return "All monitors disabled"
        }
        if (preferences.cpuEnabled && snapshot.cpu == nil)
            || (preferences.memoryEnabled && snapshot.memory == nil)
            || (preferences.networkEnabled && snapshot.network == nil) {
            return "Sampling / unavailable"
        }
        return "Monitoring"
    }

    func configure(_ preferences: Preferences) {
        let samplingChanged = self.preferences.interval != preferences.interval
            || self.preferences.cpuEnabled != preferences.cpuEnabled
            || self.preferences.memoryEnabled != preferences.memoryEnabled
            || self.preferences.networkEnabled != preferences.networkEnabled
        self.preferences = preferences
        if samplingChanged { restart() }
        else { onUpdate?() }
    }

    func toggle() { isRunning.toggle(); restart() }
    func sleep() { isSleeping = true; restart() }
    func wake() { isSleeping = false; restart() }
    func stop() { isRunning = false; restart() }

    func restart() {
        generation += 1
        let revision = generation
        snapshot = MonitoringSnapshot()
        onUpdate?()
        worker.configure(preferences, running: isRunning && !isSleeping) { [weak self] value in
            Task { @MainActor [weak self] in
                guard let self, generation == revision else { return }
                if snapshot != value { snapshot = value; onUpdate?() }
            }
        }
    }
}
