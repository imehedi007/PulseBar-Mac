import AppKit

enum MetricLevel: Equatable {
    case normal, warning, critical

    static func level(_ value: Double, thresholds: Thresholds) -> Self {
        if value >= Double(thresholds.critical) { return .critical }
        if value >= Double(thresholds.warning) { return .warning }
        return .normal
    }

    var color: NSColor {
        switch self {
        case .normal: return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 0.40, green: 0.90, blue: 0.52, alpha: 1)
                : NSColor(calibratedRed: 0.05, green: 0.40, blue: 0.15, alpha: 1)
        }
        case .warning: return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedRed: 1, green: 0.76, blue: 0.30, alpha: 1)
                : NSColor(calibratedRed: 0.55, green: 0.30, blue: 0, alpha: 1)
        }
        case .critical: return .systemRed
        }
    }
}

enum MenuBarFormatter {
    static func percent(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.0f%%", min(100, max(0, value)))
    }

    static func speed(_ bytes: Double?) -> String {
        guard let bytes, bytes.isFinite, bytes >= 0 else { return "—" }
        switch bytes {
        case 1_000_000_000...: return String(format: "%.1f GB/s", bytes / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1f MB/s", bytes / 1_000_000)
        case 1_000...: return String(format: "%.1f KB/s", bytes / 1_000)
        default: return String(format: "%.0f B/s", bytes)
        }
    }

    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_000_000_000)
    }

    static func title(snapshot: MonitoringSnapshot, preferences: Preferences, running: Bool) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
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
        metric("RAM", value: snapshot.memory?.percentage, enabled: preferences.memoryEnabled, thresholds: preferences.memoryThresholds)
        return result
    }
}
