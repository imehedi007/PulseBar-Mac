import Foundation
import Observation

struct MonitoringSnapshot: Equatable, Sendable {
    var cpu: Double?
    var memory: MemoryReading?
    var network: NetworkRate?
    var memoryPressure: MemoryPressure = .unknown
}

// Mutable monitor state is confined to this serial queue. No UI objects cross it.
private final class SamplingWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.pulsebar.sampling", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var pressureSource: DispatchSourceMemoryPressure?
    private var pressureGeneration = 0
    private var latestSnapshot = MonitoringSnapshot()
    private var cpu = CPUMonitor()
    private var network = NetworkMonitor()
    private let memory = MemoryMonitor()

    func configure(_ preferences: Preferences, running: Bool,
                   deliver: @escaping @Sendable (MonitoringSnapshot) -> Void) {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            pressureGeneration += 1
            pressureSource?.cancel()
            pressureSource = nil
            // Query current kernel pressure level if memory monitoring is enabled
            let initialPressure = (running && preferences.memoryEnabled) ? MemoryPressure.current() : .unknown
            latestSnapshot = MonitoringSnapshot(memoryPressure: initialPressure)
            cpu = CPUMonitor()
            network = NetworkMonitor()
            guard running && (preferences.cpuEnabled || preferences.memoryEnabled || preferences.networkEnabled) else { return }
            if preferences.memoryEnabled {
                let revision = pressureGeneration
                let pressure = DispatchSource.makeMemoryPressureSource(
                    eventMask: [.normal, .warning, .critical], queue: queue)
                pressure.setEventHandler { [weak self] in
                    guard let self, pressureGeneration == revision,
                          let pressureSource else { return }
                    let state = MemoryPressure(events: pressureSource.data)
                    guard state != latestSnapshot.memoryPressure else { return }
                    latestSnapshot.memoryPressure = state
                    deliver(latestSnapshot)
                }
                pressureSource = pressure
                pressure.resume()
            }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now(), repeating: preferences.interval, leeway: .milliseconds(25))
            source.setEventHandler { [weak self] in
                guard let self else { return }
                let kernelPressure = preferences.memoryEnabled ? MemoryPressure.current() : .unknown
                let pressure = kernelPressure != .unknown ? kernelPressure : latestSnapshot.memoryPressure
                latestSnapshot = MonitoringSnapshot(
                    cpu: preferences.cpuEnabled ? cpu.sample() : nil,
                    memory: preferences.memoryEnabled ? memory.sample() : nil,
                    network: preferences.networkEnabled ? network.sample() : nil,
                    memoryPressure: pressure)
                deliver(latestSnapshot)
            }
            timer = source
            source.resume()
        }
    }

    deinit {
        timer?.cancel()
        pressureSource?.cancel()
    }
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
