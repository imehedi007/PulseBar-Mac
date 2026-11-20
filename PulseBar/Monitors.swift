import Foundation
import SystemConfiguration

struct CPUTicks: Equatable, Sendable {
    var user: UInt64
    var system: UInt64
    var idle: UInt64
    var nice: UInt64

    static func utilization(previous: Self?, current: Self) -> Double? {
        guard let previous,
              current.user >= previous.user, current.system >= previous.system,
              current.idle >= previous.idle, current.nice >= previous.nice else { return nil }
        let busy = Double(current.user - previous.user) + Double(current.system - previous.system)
            + Double(current.nice - previous.nice)
        let total = busy + Double(current.idle - previous.idle)
        return total > 0 ? 100 * busy / total : 0
    }
}

struct CPUMonitor {
    private var previous: CPUTicks?

    mutating func sample() -> Double? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { previous = nil; return nil }
        let ticks = CPUTicks(user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1),
                             idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
        defer { previous = ticks }
        return CPUTicks.utilization(previous: previous, current: ticks)
    }
}

struct MemoryReading: Equatable, Sendable {
    let total: UInt64
    let used: UInt64
    var available: UInt64 { total - used }
    // A numerical VM headroom estimate, never an OS memory-pressure classification.
    // Uses the existing available estimate; inactive caches remain counted as used.
    var estimatedHeadroomPercentage: Double? {
        total > 0 ? Double(available) / Double(total) * 100 : nil
    }
    var percentage: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }

    // Memory Used matches macOS Activity Monitor:
    // App Memory (internal pages - purgeable) + Wired Memory + Compressed Memory.
    // Inactive file-backed caches are reclaimable by the kernel and excluded from used.
    // When internalPages is nil (legacy/fallback), falls back to resident - purgeable.
    static func calculate(total: UInt64, pageSize: UInt64, active: UInt64,
                          inactive: UInt64, wired: UInt64, compressed: UInt64,
                          purgeable: UInt64, internalPages: UInt64? = nil) -> Self {
        let usedPages: Double
        if let internalPages {
            let appPages = internalPages > purgeable ? Double(internalPages - purgeable) : 0
            usedPages = appPages + Double(wired) + Double(compressed)
        } else {
            let resident = Double(active) + Double(inactive) + Double(wired) + Double(compressed)
            usedPages = max(0, resident - Double(purgeable))
        }
        let bytes = usedPages * Double(pageSize)
        return Self(total: total, used: UInt64(min(Double(total), bytes)))
    }
}

enum MemoryPressure: String, Equatable, Sendable {
    case unknown = "Unknown"
    case normal = "Normal"
    case warning = "Warning"
    case critical = "Critical"

    init(events: DispatchSource.MemoryPressureEvent) {
        // Coalesced notifications may contain multiple flags; prefer the most severe.
        if events.contains(.critical) { self = .critical }
        else if events.contains(.warning) { self = .warning }
        else if events.contains(.normal) { self = .normal }
        else { self = .unknown }
    }

    /// Queries the kernel's active VM pressure level directly via sysctl.
    /// Used at startup or when edge-triggered DispatchSource events have not arrived yet.
    static func current() -> Self {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else {
            return .unknown
        }
        switch level {
        case 1: return .normal
        case 2: return .warning
        case 4...: return .critical
        default: return .unknown
        }
    }
}

struct MemoryMonitor {
    private static let systemPageSize: UInt64 = {
        var pageSize: vm_size_t = 0
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        if host_page_size(host, &pageSize) == KERN_SUCCESS && pageSize > 0 {
            return UInt64(pageSize)
        }
        return UInt64(vm_kernel_page_size)
    }()

    func sample() -> MemoryReading? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return .calculate(total: ProcessInfo.processInfo.physicalMemory, pageSize: Self.systemPageSize,
                          active: UInt64(info.active_count), inactive: UInt64(info.inactive_count),
                          wired: UInt64(info.wire_count), compressed: UInt64(info.compressor_page_count),
                          purgeable: UInt64(info.purgeable_count),
                          internalPages: UInt64(info.internal_page_count))
    }
}

struct InterfaceBytes: Equatable, Sendable {
    let received: UInt64
    let sent: UInt64
    let index: UInt32
}

struct NetworkRate: Equatable, Sendable {
    var download: Double = 0
    var upload: Double = 0
}

struct NetworkCalculator {
    private var previous: [String: InterfaceBytes]?
    private var previousTime: Double?

    mutating func sample(_ counters: [String: InterfaceBytes], time: Double) -> NetworkRate? {
        defer { previous = counters; previousTime = time }
        guard let previous, let previousTime, time > previousTime else { return nil }
        var rate = NetworkRate()
        let elapsed = time - previousTime
        for (name, value) in counters {
            guard let old = previous[name], old.index == value.index else { continue }
            // Reset each direction independently; never turn resets into traffic spikes.
            if value.received >= old.received {
                rate.download += Double(value.received - old.received) / elapsed
            }
            if value.sent >= old.sent {
                rate.upload += Double(value.sent - old.sent) / elapsed
            }
        }
        return rate
    }
}

struct NetworkMonitor {
    private var calculator = NetworkCalculator()
    private var physicalNames = Set<String>()
    private var nextDiscovery: Double = 0

    mutating func sample() -> NetworkRate? {
        let time = ProcessInfo.processInfo.systemUptime
        // Physical interface discovery is much less frequent than counter sampling.
        if time >= nextDiscovery {
            physicalNames = Set((SCNetworkInterfaceCopyAll() as? [SCNetworkInterface] ?? []).compactMap {
                let type = SCNetworkInterfaceGetInterfaceType($0)
                guard type == kSCNetworkInterfaceTypeEthernet || type == kSCNetworkInterfaceTypeIEEE80211,
                      let name = SCNetworkInterfaceGetBSDName($0) else { return nil }
                return name as String
            })
            nextDiscovery = time + 5
        }
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0 else { calculator = NetworkCalculator(); return nil }
        defer { freeifaddrs(head) }
        var counters: [String: InterfaceBytes] = [:]
        counters.reserveCapacity(4)
        var cursor = head
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let item = entry.pointee
            guard let address = item.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK,
                  item.ifa_flags & UInt32(IFF_UP) != 0,
                  item.ifa_flags & UInt32(IFF_RUNNING) != 0,
                  item.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
                  let data = item.ifa_data else { continue }
            let name = String(cString: item.ifa_name)
            guard physicalNames.contains(name) else { continue }
            let bytes = data.assumingMemoryBound(to: if_data.self).pointee
            counters[name] = InterfaceBytes(received: UInt64(bytes.ifi_ibytes),
                                           sent: UInt64(bytes.ifi_obytes), index: if_nametoindex(item.ifa_name))
        }
        return calculator.sample(counters, time: time)
    }
}
