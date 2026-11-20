import AppKit

enum MetricLevel: Equatable {
    case normal, warning, critical

    private static let normalColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 0.40, green: 0.90, blue: 0.52, alpha: 1)
            : NSColor(calibratedRed: 0.05, green: 0.40, blue: 0.15, alpha: 1)
    }

    private static let warningColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(calibratedRed: 1, green: 0.76, blue: 0.30, alpha: 1)
            : NSColor(calibratedRed: 0.55, green: 0.30, blue: 0, alpha: 1)
    }

    static func level(_ value: Double, thresholds: Thresholds) -> Self {
        if value >= Double(thresholds.critical) { return .critical }
        if value >= Double(thresholds.warning) { return .warning }
        return .normal
    }

    var color: NSColor {
        switch self {
        case .normal: return Self.normalColor
        case .warning: return Self.warningColor
        case .critical: return .systemRed
        }
    }
}

enum MenuBarFormatter {
    // Reuse the symbol while metrics refresh; it is visible only during cleaning.
    private static let keyboardImage = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Keyboard Cleaning active")?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.systemOrange]))

    private static let titleFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)

    static func cleaningIndicator(active: Bool) -> NSImage? {
        active ? keyboardImage : nil
    }

    static func memoryColor(_ pressure: MemoryPressure) -> NSColor {
        switch pressure {
        case .normal: return MetricLevel.normal.color
        case .warning: return .systemYellow
        case .critical: return .systemRed
        case .unknown: return .systemGray
        }
    }

    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.0f%%", min(100, max(0, value)))
    }

    static func speed(_ bytes: Double?) -> String {
        guard let bytes, bytes.isFinite, bytes >= 0 else { return "—" }
        let bits = bytes * 8
        guard bits.isFinite else { return "—" }
        switch bits {
        case 1_000_000_000...: return String(format: "%.1f Gbps", bits / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1f Mbps", bits / 1_000_000)
        case 1_000...: return String(format: "%.1f Kbps", bits / 1_000)
        default: return String(format: "%.0f bps", bits)
        }
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }

    static func title(snapshot: MonitoringSnapshot, preferences: Preferences, running: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = titleFont
        func append(_ text: String, color: NSColor = .labelColor) {
            result.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        }
        func metric(_ label: String, value: Double?, enabled: Bool, thresholds: Thresholds) {
            append(" | ")
            let text = enabled ? percent(value) : "off"
            append("\(label) \(text)", color: value.map { MetricLevel.level($0, thresholds: thresholds).color } ?? .secondaryLabelColor)
        }
        if !running { append("Ⅱ ") }
        append("↓ " + (preferences.networkEnabled ? speed(snapshot.network?.download) : "off"))
        append(" ↑ " + (preferences.networkEnabled ? speed(snapshot.network?.upload) : "off"))
        metric("CPU", value: snapshot.cpu, enabled: preferences.cpuEnabled, thresholds: preferences.cpuThresholds)
        append(" | ")
        let ramText = preferences.memoryEnabled ? percent(snapshot.memory?.percentage) : "off"
        let pressure = running && preferences.memoryEnabled ? snapshot.memoryPressure : .unknown
        append("RAM \(ramText)", color: memoryColor(pressure))
        return result
    }
}
