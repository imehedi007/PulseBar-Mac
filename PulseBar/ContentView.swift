import SwiftUI
import ServiceManagement

// MARK: - Reusable Info Tooltip Component
struct InfoTooltip: View {
    let tooltip: String
    @State private var isShowingPopover = false

    var body: some View {
        Button {
            isShowingPopover.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.8))
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .popover(isPresented: $isShowingPopover, arrowEdge: .trailing) {
            Text(tooltip)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .padding(10)
                .frame(maxWidth: 220)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onHover { inside in
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Status Popover (Main Menu Bar View)
struct StatusPopover: View {
    let service: MonitoringService
    let settings: SettingsManager
    let cleaning: KeyboardCleaning
    let clipboard: ClipboardManager
    let screenshot: ScreenshotManager
    var onDismissPopover: (() -> Void)? = nil
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            if showingSettings {
                settingsPageView
                    .transition(.opacity)
            } else {
                dashboardPageView
                    .transition(.opacity)
            }
        }
        .padding(14)
        .frame(width: 375, height: 470)
        .onExitCommand {
            if showingSettings {
                withAnimation(.easeInOut(duration: 0.16)) {
                    showingSettings = false
                }
            } else {
                onDismissPopover?()
            }
        }
    }

    // MARK: - Dashboard Page View
    private var dashboardPageView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: App Title, Live Status Indicator
            HStack(alignment: .center) {
                HStack(spacing: 7) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.15, green: 0.72, blue: 0.95))
                    Text("PulseBar")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(service.isRunning ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(service.status)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.primary.opacity(0.05))
                )
            }

            // Real-time Metrics Dashboard Card
            MetricsView(snapshot: service.snapshot, preferences: settings.preferences)

            // Feature Control Cards
            VStack(spacing: 8) {
                // 1. Keyboard Cleaning Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.blue)
                                .frame(width: 18)
                            Text("Keyboard Cleaning")
                                .font(.system(size: 12, weight: .semibold))
                            InfoTooltip(tooltip: "Temporarily locks keyboard input so you can wipe and clean keys without accidental input. Mouse and trackpad stay usable. Press Esc anytime to stop.")
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { cleaning.isActive },
                            set: { cleaning.setEnabled($0, seconds: settings.preferences.cleaningDuration) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("KeyboardCleaning")
                    }

                    HStack {
                        Text(cleaning.isActive
                             ? "Active — \(cleaning.remainingSeconds)s remaining. Press Esc or toggle to stop."
                             : "Ready • \(settings.preferences.cleaningDuration)s session • Esc to stop")
                            .font(.caption2)
                            .foregroundStyle(cleaning.isActive ? .orange : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                    }

                    if let message = cleaning.message {
                        HStack(spacing: 6) {
                            Text(message)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Open Accessibility") { cleaning.openPermissions() }
                                .buttonStyle(.link)
                                .font(.caption2)
                        }
                    }
                }
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.primary.opacity(0.035))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                )

                // 2. Clipboard History Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.teal)
                                .frame(width: 18)
                            Text("Clipboard History")
                                .font(.system(size: 12, weight: .semibold))
                            InfoTooltip(tooltip: "Stores copied text, images, and links locally. Press ⌘⇧V to summon the Spotlight-style search panel and auto-paste into your active app.")
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { clipboard.isEnabled },
                            set: { clipboard.setEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("ClipboardHistory")
                    }

                    HStack {
                        Text(clipboard.isEnabled
                             ? "\(clipboard.items.count) item\(clipboard.items.count == 1 ? "" : "s") saved • ⌘⇧V"
                             : "Off — clipboard capture paused.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("ClipboardStatusText")
                        Spacer()
                        if clipboard.isEnabled {
                            Button {
                                clipboard.openPanel()
                            } label: {
                                HStack(spacing: 3) {
                                    Text("Open Panel")
                                    Image(systemName: "arrow.up.forward.app")
                                        .font(.system(size: 9))
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityIdentifier("OpenClipboardPanel")
                        }
                    }

                    if let error = clipboard.shortcutConflictError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.primary.opacity(0.035))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                )

                // 3. Screenshot & Annotation Card
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.purple)
                                .frame(width: 18)
                            Text("Screenshot & Annotation")
                                .font(.system(size: 12, weight: .semibold))
                            InfoTooltip(tooltip: "Freeze-frame desktop capture inspired by Lightshot. Drag to select any area, add vector arrows, boxes, text, or highlighters, then copy with ⌘C or save with ⌘S.")
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { screenshot.isEnabled },
                            set: { screenshot.setEnabled($0) }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .accessibilityIdentifier("ScreenshotTool")
                    }

                    HStack {
                        Text(screenshot.isEnabled
                             ? "⌘⇧S to capture • Drag region • ⌘C to copy"
                             : "Off — screenshot shortcut disabled.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("ScreenshotStatusText")
                        Spacer()
                        if screenshot.isEnabled {
                            Button {
                                onDismissPopover?()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                    screenshot.startCapture()
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Text("Capture")
                                    Image(systemName: "camera")
                                        .font(.system(size: 9))
                                }
                            }
                            .buttonStyle(.borderless)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.purple)
                            .accessibilityIdentifier("TakeScreenshotButton")
                        }
                    }

                    if let error = screenshot.shortcutConflictError {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if screenshot.permissionDenied {
                        Button("Grant Screen Recording Permission…") {
                            ScreenshotCaptureService.requestPermission()
                        }
                        .font(.caption2)
                        .buttonStyle(.link)
                    }
                }
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.primary.opacity(0.035))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.06), lineWidth: 0.5))
                )
            }

            Spacer(minLength: 4)

            // Bottom Action Bar
            HStack(spacing: 8) {
                Button {
                    service.toggle()
                } label: {
                    Label(service.isRunning ? "Pause" : "Resume", systemImage: service.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("PauseResume")

                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showingSettings = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                        Text("Settings")
                        Image(systemName: "chevron.forward")
                            .font(.system(size: 8))
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("Settings")

                Spacer()

                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quit")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Settings Page View
    private var settingsPageView: some View {
        VStack(spacing: 10) {
            // Settings Header Bar
            HStack(alignment: .center) {
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showingSettings = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Dashboard")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("Settings")

                Spacer()

                Text("Preferences")
                    .font(.system(size: 13, weight: .bold, design: .rounded))

                Spacer()

                Button("Done") {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        showingSettings = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.bottom, 2)

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                SettingsView(settings: settings)
                    .padding(.vertical, 2)
                    .padding(.trailing, 4)
            }
        }
    }
}

// MARK: - Metrics Dashboard View
private struct MetricsView: View {
    let snapshot: MonitoringSnapshot
    let preferences: Preferences

    var body: some View {
        VStack(spacing: 8) {
            // Top Stat Cards (CPU, RAM, Network)
            HStack(spacing: 8) {
                // CPU Card
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "cpu")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("CPU")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(preferences.cpuEnabled ? MenuBarFormatter.percent(snapshot.cpu) : "Disabled")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(color(snapshot.cpu, thresholds: preferences.cpuThresholds))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )

                // RAM Card
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "memorychip")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("RAM")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(preferences.memoryEnabled ? MenuBarFormatter.percent(snapshot.memory?.percentage) : "Disabled")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(nsColor: MenuBarFormatter.memoryColor(preferences.memoryEnabled ? snapshot.memoryPressure : .unknown)))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )

                // Network Card
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "network")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Network")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    if preferences.networkEnabled {
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.blue)
                                Text(MenuBarFormatter.speed(snapshot.network?.download))
                                    .font(.system(size: 10, weight: .medium))
                                    .monospacedDigit()
                            }
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.purple)
                                Text(MenuBarFormatter.speed(snapshot.network?.upload))
                                    .font(.system(size: 10, weight: .medium))
                                    .monospacedDigit()
                            }
                        }
                    } else {
                        Text("Disabled")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.04))
                )
            }

            // Detailed System & Memory Metrics Grid
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 5) {
                GridRow {
                    HStack(spacing: 4) {
                        Text("OS Reported")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        InfoTooltip(tooltip: "macOS kernel reported virtual memory pressure level (Normal, Warning, or Critical).")
                    }
                    Text(preferences.memoryEnabled ? snapshot.memoryPressure.rawValue : "Disabled")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color(nsColor: MenuBarFormatter.memoryColor(preferences.memoryEnabled ? snapshot.memoryPressure : .unknown)))
                        .accessibilityIdentifier("MemoryPressureStatus")

                    HStack(spacing: 4) {
                        Text("Used / Total")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(snapshot.memory.map {
                        "\(MenuBarFormatter.gigabytes($0.used)) / \(MenuBarFormatter.gigabytes($0.total)) GB"
                    } ?? "—")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                }

                GridRow {
                    HStack(spacing: 4) {
                        Text("Estimated headroom")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        InfoTooltip(tooltip: "Calculated available memory headroom: (total − memory used) / total.")
                    }
                    Text(preferences.memoryEnabled
                         ? snapshot.memory?.estimatedHeadroomPercentage.map { "\(MenuBarFormatter.percent($0)) available" } ?? "Unavailable"
                         : "Disabled")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("EstimatedMemoryHeadroom")

                    HStack(spacing: 4) {
                        Text("Available")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(snapshot.memory.map { "\(MenuBarFormatter.gigabytes($0.available)) GB" } ?? "—")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                GridRow {
                    HStack(spacing: 4) {
                        Text("Download")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(preferences.networkEnabled ? MenuBarFormatter.speed(snapshot.network?.download) : "Disabled")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text("Upload")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(preferences.networkEnabled ? MenuBarFormatter.speed(snapshot.network?.upload) : "Disabled")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.025))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.05), lineWidth: 0.5))
            )
        }
    }

    private func color(_ value: Double?, thresholds: Thresholds) -> Color {
        value.map { Color(nsColor: MetricLevel.level($0, thresholds: thresholds).color) } ?? .secondary
    }
}

// MARK: - Organized Settings View
struct SettingsView: View {
    let settings: SettingsManager

    private func binding<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { settings.preferences[keyPath: keyPath] },
                set: { value in settings.update { $0[keyPath: keyPath] = value } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group 1: System Monitoring Settings
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("Monitoring")
                        .font(.system(size: 12, weight: .bold))
                    InfoTooltip(tooltip: "Select which metrics PulseBar monitors and displays in your menu bar.")
                    Spacer()
                }

                HStack(spacing: 16) {
                    Toggle("CPU", isOn: binding(\.cpuEnabled))
                    Toggle("Memory", isOn: binding(\.memoryEnabled))
                    Toggle("Network", isOn: binding(\.networkEnabled))
                }
                .font(.caption)

                HStack {
                    Picker("Refresh", selection: binding(\.interval)) {
                        Text("500 ms").tag(0.5)
                        Text("1 s").tag(1.0)
                        Text("2 s").tag(2.0)
                        Text("5 s").tag(5.0)
                    }
                    .font(.caption)

                    InfoTooltip(tooltip: "Frequency at which CPU, memory, and network metrics are refreshed.")
                }

                ThresholdEditor(title: "CPU", thresholds: binding(\.cpuThresholds))

                Toggle("Start monitoring automatically", isOn: binding(\.autoStart))
                    .font(.caption)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.05), lineWidth: 0.5))
            )

            // Group 2: Tools & Shortcuts Preferences
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.purple)
                    Text("Tools & History")
                        .font(.system(size: 12, weight: .bold))
                    InfoTooltip(tooltip: "Configure cleaning timer, clipboard storage limit, and screenshot preferences.")
                    Spacer()
                }

                HStack {
                    Picker("Cleaning duration", selection: binding(\.cleaningDuration)) {
                        Text("15 seconds").tag(15)
                        Text("30 seconds").tag(30)
                        Text("60 seconds").tag(60)
                        Text("120 seconds").tag(120)
                    }
                    .font(.caption)
                    .accessibilityIdentifier("CleaningDuration")

                    InfoTooltip(tooltip: "Duration keyboard input remains safely locked during a physical cleaning session.")
                }

                HStack {
                    Picker("Clipboard history limit", selection: binding(\.clipboardLimit)) {
                        Text("25 items").tag(25)
                        Text("50 items").tag(50)
                        Text("100 items").tag(100)
                        Text("200 items").tag(200)
                    }
                    .font(.caption)
                    .accessibilityIdentifier("ClipboardLimit")

                    InfoTooltip(tooltip: "Maximum number of clipboard history items stored on disk.")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Screenshot & Annotation Tool (⌘⇧S)", isOn: binding(\.screenshotEnabled))
                        .font(.caption)
                        .accessibilityIdentifier("ScreenshotEnabledToggle")

                    Toggle("Auto-save screenshots to Pictures/Screenshots", isOn: binding(\.screenshotAutoSave))
                        .font(.caption)
                        .disabled(!settings.preferences.screenshotEnabled)
                        .accessibilityIdentifier("ScreenshotAutoSaveToggle")

                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10))
                        Button("Open Screenshots Folder") {
                            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/Screenshots")
                            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                        }
                        .font(.caption2)
                        .buttonStyle(.link)
                    }
                    .padding(.leading, 18)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.05), lineWidth: 0.5))
            )

            // Group 3: General & Startup
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("General")
                        .font(.system(size: 12, weight: .bold))
                    InfoTooltip(tooltip: "Launch settings and baseline reset options.")
                    Spacer()
                }

                HStack {
                    Toggle("Launch at login", isOn: Binding(get: { settings.loginEnabled }, set: { settings.setLoginEnabled($0) }))
                        .font(.caption)
                        .disabled(settings.loginBusy)

                    InfoTooltip(tooltip: "Starts PulseBar in the menu bar automatically when logging in.")
                }

                if settings.loginNeedsApproval {
                    Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                        .font(.caption2)
                }
                if let error = settings.loginError {
                    Text(error).font(.caption2).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                    Text("RAM colors follow macOS memory pressure. Available includes reclaimable pages.")
                        .font(.system(size: 10))
                }
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Divider()

                HStack {
                    Spacer()
                    Button("Restore Defaults") { settings.restoreDefaults() }
                        .controlSize(.small)
                        .disabled(settings.loginBusy)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.primary.opacity(0.03))
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.05), lineWidth: 0.5))
            )
        }
        .toggleStyle(.checkbox)
    }
}

// MARK: - Threshold Editor Component
private struct ThresholdEditor: View {
    let title: String
    @Binding var thresholds: Thresholds

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text("\(title) thresholds")
                    .font(.caption.weight(.semibold))
                InfoTooltip(tooltip: "Percentage thresholds for Warning (yellow) and Critical (red) menu bar highlights.")
            }
            HStack(spacing: 12) {
                Stepper("Warning \(thresholds.warning)%", value: $thresholds.warning, in: 1...(thresholds.critical - 1))
                Stepper("Critical \(thresholds.critical)%", value: $thresholds.critical, in: (thresholds.warning + 1)...100)
            }
            .font(.caption2)
        }
    }
}
