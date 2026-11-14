# pulseBar Mac

**PulseBar** is a lightweight, native macOS menu-bar system monitor that keeps CPU, memory, download and upload activity visible in one indicator.

```text
↓ 99.2 Mbps ↑ 16.8 Mbps | CPU 34% | RAM 68%
```

## Features

- One compact monospaced menu-bar indicator; no Dock icon or launch window.
- Configurable CPU utilization thresholds and independent RAM colors driven by macOS memory pressure.
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

Click the single menu-bar indicator for details, pause/resume, settings and quit. All three monitors default on with a 500 ms interval and automatic start. Choose 500 ms, 1 s, 2 s or 5 s; CPU retains configurable warning (75%) and critical (90%) thresholds. RAM percentage is unchanged, but its color follows macOS memory pressure: Normal = green, Warning = yellow, Critical = red, Unknown = grey. The popover shows pressure separately from RAM utilization. Old saved RAM thresholds remain readable for preference compatibility but have no effect and are no longer offered in settings. Settings persist in UserDefaults. Restore Defaults also disables launch at login. Automatic start controls the next launch; pause is session-only. Disabled or unavailable metrics display an explicit placeholder. The first CPU/network reading needs two samples.

## Measurement definitions

- CPU: Mach HOST_CPU_LOAD_INFO aggregate user/system/nice tick differences divided by total tick differences, including idle. Scale is 0–100% across all cores. Counter decreases discard the interval and establish a new baseline.
- RAM: (active + inactive + wired + compressor-resident − purgeable) pages × native page size, clamped to physical RAM. Available = total − used. This estimate counts non-purgeable inactive pages as used; reclaimable cache can make it differ from Activity Monitor. It is not memory pressure and does not measure swap or allocation latency. GB uses decimal units.
- Network: getifaddrs link-layer byte counters for active physical Ethernet/Wi-Fi interfaces discovered by SystemConfiguration. Rates use monotonic elapsed time, not an assumed timer interval. Each physical interface is counted once; loopback, VPN tunnels, bridges and other virtual interfaces are excluded to avoid counting the same traffic twice. VPN traffic is represented by its physical transport bytes. Newly connected interfaces establish a baseline, removed interfaces disappear, and reset/wrapped counters discard that direction's interval. Interface discovery refreshes every five seconds, so hot-plug detection can take that long. The monitor computes bytes per second internally; the display uses decimal bits per second.

Network display converts the monitor's bytes per second to bits per second by multiplying by 8. Units are decimal: bps, Kbps (1,000 bps), Mbps (1,000,000 bps) and Gbps (1,000,000,000 bps). Kbps, Mbps and Gbps display one decimal place; bps displays whole bits per second. For example, 1 MB/s displays as 8.0 Mbps, 5 MB/s as 40.0 Mbps, 10 MB/s as 80.0 Mbps, and 512 B/s as 4.1 Kbps. Byte-counter calculations and the default 500 ms sampling interval are unchanged.

## Architecture and resource use

Memory pressure uses Apple's public `DispatchSource.makeMemoryPressureSource` with normal, warning and critical events on the existing sampling queue. It introduces no polling timer. Dispatch reports changes and does not guarantee an initial state: pressure is Unknown until a notification arrives, potentially indefinitely on a stable system. High utilization never substitutes for an OS pressure event. For example, RAM 92% with Normal pressure is green; RAM 60% with Critical pressure is red. Coalesced event flags use the most severe reported state.

Pause, sleep, memory-disable and shutdown cancel the pressure source. Resume, wake, re-enable and sampling reconfiguration start a fresh subscription at Unknown. Generation checks reject callbacks from older subscriptions; periodic metric samples retain the latest pressure state. Pressure events update the existing snapshot immediately. This is a categorical OS notification, not a reproduction of Activity Monitor's pressure graph.

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

The latest local run passed **17 tests**: 16 Swift Testing tests and one UI automation test. Coverage includes CPU deltas, first samples, resets, memory calculations, network rates, multiple interfaces, zero traffic, unit formatting, threshold transitions, independent colors, disabled metrics formatting, threshold normalization bounds, settings persistence and monitoring lifecycle. Focused pressure tests cover all event states, coalesced flags, transitions in light/dark appearances, 92% utilization with Normal pressure, 60% with Critical pressure, ignored legacy RAM thresholds, inactive grey rendering, and pause/sleep/wake/re-enable resets. The UI test checks the pressure-status row, pauses/resumes monitoring and opens settings.

### RAM pressure QA — 2026-11-14

- Debug build with test targets: passed.
- Full test suite: 17 passed, 0 failed, 0 skipped.
- Release build: passed on Apple Silicon using `xcodebuild -project PulseBar.xcodeproj -scheme PulseBar -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/PulseBar-Release-QA build`.
- The first Release attempt was blocked by the workspace sandbox's restriction on Swift macro compiler processes; the same build succeeded outside that sandbox. Xcode emitted only an App Intents metadata-extraction notice because this app does not use App Intents.
- Actual system-wide warning/critical pressure was not induced. Event mappings are tested with synthetic Dispatch event flags; lifecycle tests exercise real source creation/cancellation and the service's sleep/wake methods. Physical sleep/wake and OS-driven pressure transitions remain manual QA checks.
- Manual follow-up: on a test Mac, compare the popover's pressure state with OS-reported transitions, verify recovery to green after a Normal notification, and confirm pause/disable/sleep clears stale pressure. Do not expect green before the first notification.

Run the suite using **Product > Test (⌘U)**. Tests do not enable launch at login or alter your saved monitoring preferences.

## Privacy and limitations

All readings stay on your Mac. PulseBar does not collect analytics, send telemetry or require administrator privileges for ordinary monitoring. Network rates describe physical transport traffic rather than per-process usage. RAM percentage is an estimate, not Activity Monitor's memory-pressure measurement. Login-at-login approval and Intel hardware remain unverified.
