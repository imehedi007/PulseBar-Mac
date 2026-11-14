import SwiftUI
import ServiceManagement

struct StatusPopover: View {
    let service: MonitoringService
    let settings: SettingsManager
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("PulseBar").font(.headline)
                Spacer()
                Text(service.status).font(.caption).foregroundStyle(.secondary)
            }
            MetricsView(snapshot: service.snapshot, preferences: settings.preferences)
            Divider()
            HStack {
                Button(service.isRunning ? "Pause" : "Resume") { service.toggle() }
                    .accessibilityIdentifier("PauseResume")
                Button(showingSettings ? "Hide Settings" : "Settings") { showingSettings.toggle() }
                    .accessibilityIdentifier("Settings")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            if showingSettings {
                Divider()
                SettingsView(settings: settings)
            }
        }
        .padding(16)
        .frame(width: 370)
    }
}

private struct MetricsView: View {
    let snapshot: MonitoringSnapshot
    let preferences: Preferences

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 10) {
            GridRow {
                Text("CPU")
                Text(preferences.cpuEnabled ? MenuBarFormatter.percent(snapshot.cpu) : "Disabled")
                    .foregroundStyle(color(snapshot.cpu, thresholds: preferences.cpuThresholds))
            }
            GridRow {
                Text("RAM")
                Text(preferences.memoryEnabled ? MenuBarFormatter.percent(snapshot.memory?.percentage) : "Disabled")
                    .foregroundStyle(color(snapshot.memory?.percentage, thresholds: preferences.memoryThresholds))
            }
            GridRow {
                Text("Used / Total").foregroundStyle(.secondary)
                Text(snapshot.memory.map {
                    "\(MenuBarFormatter.gigabytes($0.used)) / \(MenuBarFormatter.gigabytes($0.total)) GB"
                } ?? "—")
            }
            GridRow {
                Text("Available").foregroundStyle(.secondary)
                Text(snapshot.memory.map { "\(MenuBarFormatter.gigabytes($0.available)) GB" } ?? "—")
            }
            GridRow {
                Text("Download")
                Text(preferences.networkEnabled ? MenuBarFormatter.speed(snapshot.network?.download) : "Disabled")
            }
            GridRow {
                Text("Upload")
                Text(preferences.networkEnabled ? MenuBarFormatter.speed(snapshot.network?.upload) : "Disabled")
            }
        }
        .monospacedDigit()
    }

    private func color(_ value: Double?, thresholds: Thresholds) -> Color {
        value.map { Color(nsColor: MetricLevel.level($0, thresholds: thresholds).color) } ?? .secondary
    }
}

struct SettingsView: View {
    let settings: SettingsManager

    private func binding<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { settings.preferences[keyPath: keyPath] },
                set: { value in settings.update { $0[keyPath: keyPath] = value } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monitoring").font(.headline)
            HStack {
                Toggle("CPU", isOn: binding(\.cpuEnabled))
                Toggle("Memory", isOn: binding(\.memoryEnabled))
                Toggle("Network", isOn: binding(\.networkEnabled))
            }
            Picker("Refresh", selection: binding(\.interval)) {
                Text("500 ms").tag(0.5)
                Text("1 s").tag(1.0)
                Text("2 s").tag(2.0)
                Text("5 s").tag(5.0)
            }
            ThresholdEditor(title: "CPU", thresholds: binding(\.cpuThresholds))
            ThresholdEditor(title: "RAM", thresholds: binding(\.memoryThresholds))
            Toggle("Start monitoring automatically", isOn: binding(\.autoStart))
            Toggle("Launch at login", isOn: Binding(get: { settings.loginEnabled }, set: { settings.setLoginEnabled($0) }))
                .disabled(settings.loginBusy)
            if settings.loginNeedsApproval {
                Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let error = settings.loginError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            Text("RAM is estimated resident usage, not memory pressure. Available includes reclaimable pages.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Restore Defaults") { settings.restoreDefaults() }
                .disabled(settings.loginBusy)
        }
        .toggleStyle(.checkbox)
    }
}

private struct ThresholdEditor: View {
    let title: String
    @Binding var thresholds: Thresholds

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(title) thresholds").font(.subheadline.bold())
            HStack {
                Stepper("Warning \(thresholds.warning)%", value: $thresholds.warning, in: 1...(thresholds.critical - 1))
                Stepper("Critical \(thresholds.critical)%", value: $thresholds.critical, in: (thresholds.warning + 1)...100)
            }
            .font(.caption)
        }
    }
}
