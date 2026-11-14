# pulseBar Mac

**PulseBar** is a lightweight, native macOS menu-bar system monitor that keeps CPU, memory, download and upload activity visible in one indicator.

```text
↓ 12.4 MB/s ↑ 2.1 MB/s | CPU 34% | RAM 68%
```

## Features

- One compact monospaced menu-bar indicator; no Dock icon or launch window.
- Independent CPU and RAM warning colors, with configurable thresholds.
- Native popover with detailed readings, pause/resume, settings and quit.
- Configurable 500 ms, 1 s, 2 s and 5 s refresh intervals.
- Persistent preferences, automatic monitoring and optional launch at login.
- Background sampling with no external dependencies, cloud services or helper processes.

## Requirements

Native macOS menu-bar CPU, RAM, download and upload monitor. Requires macOS 14 or later; uses SwiftUI, AppKit, Mach, SystemConfiguration and ServiceManagement with no external dependencies.

## Build and install

Open the existing PulseBar project in Xcode, select the PulseBar scheme and My Mac, then Build/Run. Select your signing team if required. Use Product > Test for the Swift Testing calculation/settings tests and the menu-bar UI test. UI testing requires an unlocked desktop and permission for Xcode automation.

1. Clone this repository or download its ZIP and extract it.
2. Open `PulseBar.xcodeproj` with a compatible Xcode version.
3. Select the **PulseBar** scheme and **My Mac** destination.
4. Choose your development team under **Signing & Capabilities**, then press **⌘R**.

The project was built and tested with the installed Xcode toolchain on macOS 27.2. Its deployment target is macOS 14. Older Xcode releases may need project-format migration; compatibility with them has not been verified.

For installation, build/archive Release and copy PulseBar.app into /Applications. Launch it there before enabling Launch at login. macOS may require approval in System Settings > General > Login Items; the app displays a link when approval is pending. Registration errors appear in settings. Distribution to other Macs requires appropriate signing/notarization. Launch-at-login state is owned and persisted by macOS, and refreshed whenever the popover opens.

## Usage

Click the single menu-bar indicator for details, pause/resume, settings and quit. All three monitors default on with a 500 ms interval and automatic start. Choose 500 ms, 1 s, 2 s or 5 s; CPU and RAM each have independent warning (75%) and critical (90%) thresholds. Settings persist in UserDefaults. Restore Defaults also disables launch at login. Automatic start controls the next launch; pause is session-only. Disabled or unavailable metrics display an explicit placeholder. The first CPU/network reading needs two samples.

## Measurement definitions

- CPU: Mach HOST_CPU_LOAD_INFO aggregate user/system/nice tick differences divided by total tick differences, including idle. Scale is 0–100% across all cores. Counter decreases discard the interval and establish a new baseline.
- RAM: (active + inactive + wired + compressor-resident − purgeable) pages × native page size, clamped to physical RAM. Available = total − used. This estimate counts non-purgeable inactive pages as used; reclaimable cache can make it differ from Activity Monitor. It is not memory pressure and does not measure swap or allocation latency. GB uses decimal units.
- Network: getifaddrs link-layer byte counters for active physical Ethernet/Wi-Fi interfaces discovered by SystemConfiguration. Rates use monotonic elapsed time, not an assumed timer interval. Each physical interface is counted once; loopback, VPN tunnels, bridges and other virtual interfaces are excluded to avoid counting the same traffic twice. VPN traffic is represented by its physical transport bytes. Newly connected interfaces establish a baseline, removed interfaces disappear, and reset/wrapped counters discard that direction's interval. Interface discovery refreshes every five seconds, so hot-plug detection can take that long. KB/MB/GB per second use decimal bytes, not bits.

## Architecture and resource use

| File | Responsibility |
| --- | --- |
| `PulseBarApp.swift` | Application lifecycle and menu-bar-only startup |
| `Monitors.swift` | Native CPU, memory and physical-interface readers |
| `MonitoringService.swift` | Background timer, snapshots, pause and sleep handling |
| `MenuBarController.swift` | Status item and native popover |
| `MenuBarFormatter.swift` | Units, thresholds and independent metric colors |
| `ContentView.swift` | SwiftUI status details and settings |
| `SettingsManager.swift` | UserDefaults preferences and login-item registration |

Monitors.swift contains native readers and pure calculation types. MonitoringService owns a single utility-queue dispatch timer with 25 ms leeway. It cancels sampling when paused, asleep, or all monitors are disabled, and resets baselines on resume and configuration changes. Mach ports and interface lists are released on every read. Only snapshots reach the main actor; unchanged snapshots and unchanged menu-bar strings avoid UI updates. SettingsManager, MenuBarFormatter, MenuBarController and the SwiftUI popover keep presentation separate from sampling. No shell processes or logging run in the app.

CPU/RAM overhead has not been profiled. Measure a Release build outside the Xcode debugger for representative consumption. Apple Silicon is the primary tested platform; the code uses architecture-neutral APIs but Intel hardware has not been tested. On crowded/notched menu bars macOS may hide a wide status item; free menu-bar space if needed. Login-item approval and visual appearance should be verified on the intended deployment Macs.

## Tests

The latest local run passed **11 tests**: 10 Swift Testing tests and one UI automation test. Coverage includes CPU deltas, first samples, resets, memory calculations, network rates, multiple interfaces, zero traffic, unit formatting, threshold transitions, independent colors, settings persistence and monitoring lifecycle. The UI test opens the popover, pauses/resumes monitoring and opens settings.

Run the suite using **Product > Test (⌘U)**. Tests do not enable launch at login or alter your saved monitoring preferences.

## Privacy and limitations

All readings stay on your Mac. PulseBar does not collect analytics, send telemetry or require administrator privileges for ordinary monitoring. Network rates describe physical transport traffic rather than per-process usage. RAM percentage is an estimate, not Activity Monitor's memory-pressure measurement. Login-at-login approval and Intel hardware remain unverified.
