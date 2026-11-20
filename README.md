# pulseBar Mac

**PulseBar** is a lightweight, native macOS menu-bar system monitor that keeps CPU, memory, download and upload activity visible in one indicator, paired with a private, native macOS Clipboard History manager and keyboard cleaning lock.

```text
↓ 99.2 Mbps ↑ 16.8 Mbps | CPU 34% | RAM 68%
```

## Features

- One compact monospaced menu-bar indicator; no Dock icon or launch window.
- Configurable CPU utilization thresholds and independent RAM colors driven by macOS memory pressure.
- Native popover with detailed readings, pause/resume, settings and quit.
- Configurable 500 ms, 1 s, 2 s and 5 s refresh intervals.
- **Native Clipboard History (Spotlight-Style)**:
  - Instant Spotlight-style floating two-column panel triggered via global shortcut **⌘ + Shift + V**.
  - ON/OFF toggle in the popover to capture copied content or stop immediately.
  - Multi-format support: plain text, web URLs, images (with 115 px thumbnails, aspect ratio preservation, dimensions, file size, and enlarged inspector preview) and Finder file references (with native Finder icons).
  - Dedicated right-column detail inspector with sharp image previews, metadata, and quick actions.
  - Live search field with instant filtering as you type.
  - Reliable keyboard navigation (↑/↓ to navigate, ↵ to restore/paste, Esc to close).
  - Direct pasting into the previously focused application via Accessibility APIs (`postToPid`), with unambiguous fallback guidance when Accessibility is unavailable.
  - In-memory `ImageCache` preventing disk decoding overhead.
  - Deduplication (moves identical copied items to top) and configurable history limit (25, 50, 100, 200 items).
  - Clear All with confirmation dialog, individual restore/paste and delete buttons.
  - Complete privacy: strictly local storage, ignores password-manager transient/concealed items, never transmits clipboard data externally.
- **Keyboard Cleaning**: Session-only keyboard lock with customizable duration (15s, 30s, 60s, 120s) and menu-bar indicator.
- Persistent preferences, automatic monitoring and optional launch at login.
- Background sampling with no external dependencies, cloud services or helper processes.

## Requirements

Native macOS menu-bar CPU, RAM, download/upload monitor and clipboard manager. Requires macOS 14 or later; uses SwiftUI, AppKit, Carbon, Mach, SystemConfiguration and ServiceManagement with no external dependencies.

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
| `MenuBarController.swift` | Status item, popover, clipboard service lifecycle and event wiring |
| `MenuBarFormatter.swift` | Units, thresholds, cleaning indicator and independent metric colors |
| `ContentView.swift` | SwiftUI status details, clipboard history toggle and settings |
| `SettingsManager.swift` | UserDefaults preferences, clipboard limits and login-item registration |
| `ClipboardManager.swift` | Native pasteboard monitoring, format classification, deduplication and storage |
| `ClipboardHotKey.swift` | Carbon global hotkey registration (`⌘ + Shift + V`) and conflict handling |
| `ClipboardPanelController.swift` | Spotlight-style floating panel, image previews, inspector, keyboard navigation & auto-paste |

Monitors.swift contains native readers and pure calculation types. MonitoringService owns a single utility-queue dispatch timer with 25 ms leeway. It cancels sampling when paused, asleep, or all monitors are disabled, and resets baselines on resume and configuration changes. Mach ports and interface lists are released on every read. Only snapshots reach the main actor; unchanged snapshots and unchanged menu-bar strings avoid UI updates. SettingsManager, MenuBarFormatter, MenuBarController and the SwiftUI popover keep presentation separate from sampling. No shell processes or logging run in the app.

Previously collected Release measurements and their limitations are preserved in [QA_REPORT.md](QA_REPORT.md). Apple Silicon is the primary tested platform; Intel hardware has not been tested. On crowded/notched menu bars macOS may hide a wide status item; free menu-bar space if needed. Login-item approval and visual appearance should be verified on the intended deployment Macs.

### Initial pressure and estimated headroom

The popover distinguishes **OS Reported** memory pressure from **Estimated headroom**. No documented public macOS API providing a reliable initial system-pressure snapshot was identified. Dispatch source data is read only inside its event handler; undocumented sysctl keys and private APIs are not used. See Apple's [memory-pressure source documentation](https://developer.apple.com/documentation/dispatch/dispatchsourcememorypressure) and [source data contract](https://developer.apple.com/documentation/dispatch/dispatch_source_get_data).

OS Reported remains Unknown (grey) until an event arrives. Estimated headroom becomes available with the first successful existing VM sample: `100 × (total − estimated used RAM) / total`, displayed as a numerical percentage available. This reuses the public Mach statistics and the unchanged RAM formula above, without another timer or system call. It counts non-purgeable inactive caches as used, so it is not a prediction of allocation capacity, a pressure level, or Activity Monitor's pressure graph. No arbitrary Normal/Warning/Critical categories are assigned to the estimate, and it never controls RAM colours. For example, 92% RAM displays 8% estimated headroom; OS Normal still makes RAM green, while OS Critical makes it red regardless of the estimate.

Before a sample, after pause/sleep, or on a failed memory read, estimated headroom is Unavailable; when memory monitoring is disabled it is Disabled. Resume/wake starts a fresh OS subscription at Unknown and repopulates the estimate from a fresh sample at the existing interval.

## Native Clipboard History

PulseBar includes a native, privacy-first Clipboard History manager inspired by One Menu Pro.

### 1. Monitoring & Privacy
- **Toggle switch** in the popover enables or disables clipboard capture instantly.
- When enabled, monitors `NSPasteboard.general` change count at the 500 ms interval. Zero reads or allocations occur when `changeCount` is unchanged.
- When disabled, polling timers stop immediately; nothing is captured.
- **Privacy by Design**: All history metadata is stored locally in `~/Library/Application Support/PulseBar/Clipboard/history.json`. Images are saved locally as PNG files under `Images/` to avoid memory bloat. No data is ever transmitted over the network.
- **Password Manager Protection**: Clipboard items containing `org.nspasteboard.TransientType`, `org.nspasteboard.ConcealedType`, or `org.nspasteboard.AutoGeneratedType` (standard markers used by 1Password, Bitwarden, Apple Keychain) are automatically excluded.
- **In-Memory Image Caching**: An `NSCache` instance caches up to 60 MB of decoded images in memory, preventing continuous disk reads and decompression during scrolling or selection.

### 2. Supported Formats
- **Plain Text**: Formatted with preview title, line count, character count, and multiline truncation.
- **Web URLs**: Detected and badged with link icon, displaying hostname, full URL, and direct browser open button.
- **Images**: Screenshots and copied image data are saved to disk with dimensions (e.g. `1920 × 1080 px`), file size, 115 px wide row thumbnails preserving aspect ratios, and an enlarged inspector preview.
- **File References**: Finder file copies are stored with file paths, file names, folder hierarchy subtitles, and native macOS icons resolved via `NSWorkspace.shared.icon(forFile:)`.

### 3. Global Shortcut & Spotlight Panel
- **Shortcut**: Register `⌘ + Shift + V` system-wide using Carbon Event HotKey APIs. Opens the history panel even when PulseBar is not focused.
- **Conflict Handling**: If another application reserves `⌘ + Shift + V`, PulseBar catches the conflict gracefully without crashing and displays a notice in the popover.
- **Spotlight-Style Two-Column Panel**:
  - Dark translucent floating panel (700 × 480 pt) with material blur, rounded corners, and shadow.
  - Left column: search field and list of entries with custom row badges / 115 px thumbnails.
  - Right column: detail inspector with enlarged image preview, text snippet viewer, or file/URL actions.
  - Search field receives immediate keyboard focus on appearance.
  - Typing immediately filters history across titles, subtitles, text content, URLs, and file names.
  - Up and Down arrow keys navigate entries without losing search field focus or interfering with the text cursor.
  - **Enter** restores the currently selected entry and pastes into the previous application.
  - **Escape** or clicking outside closes the panel.
  - Individual **Restore** and **Delete** buttons per entry.
  - **Clear All** button with a native confirmation dialog to prevent accidental deletion.
  - Empty states for zero history and no matching search results.

### 4. Direct Pasting & Focus Restoration
- Captures the previously active application before opening the panel (`NSWorkspace.shared.frontmostApplication`).
- When Accessibility permissions are granted (`AXIsProcessTrusted()`), selecting an entry closes the panel, re-activates the target application, and simulates `⌘V` via `CGEvent.postToPid`.
- If Accessibility permissions are not granted, content is restored to `NSPasteboard.general` and an on-screen toast clearly instructs the user: *"Copied to clipboard — Press ⌘V to paste"*.
- PulseBar never claims a direct paste succeeded when only clipboard restoration occurred, and never pastes into PulseBar itself.

### 5. Deduplication & Configurable History Limit
- Copying an existing item moves it to the top (newest first) with an updated timestamp rather than creating duplicate entries.
- History limit is configurable in Settings (25, 50, 100, 200 items; default 50).
- Pruning automatically purges old entries and deletes orphaned image files from disk.

## Keyboard Cleaning

The popover includes a **Keyboard Cleaning** switch with a keyboard icon. It starts off on every launch and is never persisted. When active, a native session event tap suppresses ordinary keyboard down/up, modifier and system-defined media-key events; mouse and trackpad events remain available. No keystrokes are stored or transmitted.

- Click the switch off with your mouse, or press **Escape**, to stop immediately.
- Choose **15, 30, 60 or 120 seconds** in Settings → Cleaning duration (default **30 seconds**). This preference persists across launches and applies on the next activation; changing it does not extend an active session. Older preferences retain their monitoring settings and default to 30 seconds.
- The popover shows seconds remaining while active. An orange **keyboard** symbol appears alongside the existing menu-bar metrics and disappears when cleaning ends, including while monitoring is paused.
- Cleaning automatically ends at the selected deadline, including when the popover is closed. Do not assume protection after that deadline.
- Sleep, session deactivation, application termination, or macOS disabling the event tap ends cleaning. An unresponsive tap is not automatically re-enabled. macOS removes the tap if the process exits.
- Enable PulseBar in **System Settings → Privacy & Security → Accessibility** before using the feature. The popover explains missing permission and offers a Settings button; it never displays Active when tap creation fails. If macOS also requires Input Monitoring, enable PulseBar there and relaunch. Ordinary system monitoring needs neither permission.
- Secure Keyboard Entry, login/lock screens, Touch ID and hardware power controls are not covered. Activation is rejected if Secure Keyboard Entry is already enabled; this is a convenience feature, not a security lock or a guarantee that every hardware control is disabled.

## Tests

The full test suite passes **46 tests** (45 Swift Testing unit tests and one UI test), with zero failures or skips:
- **19 Clipboard tests**: Text/URL/image/file capture, formatting, deduplication, history limit pruning, disk cleanup, persistence across launches, pasteboard restoration, deletion, Clear All, instant search filtering, keyboard navigation (up/down clamping), toggle on/off capture lifecycle, preferences persistence/normalization, hotkey conflict handling, in-memory `ImageCache` eviction, selection clamping upon deletion, target app validation, and native file icon resolution.
- **9 Keyboard Cleaning tests**: Activation/deactivation, duration persistence, countdown, timeout, emergency exit, and pointer-event preservation.
- **17 System Monitor tests**: CPU deltas, Mach VM memory calculations, network rates, multi-interface delta calculations, units, thresholds, colors, lifecycle, and memory pressure transitions.
- **1 UI Automation test**: Menu-bar popover presentation, pause/resume toggle, memory pressure status, keyboard cleaning switch, clipboard history switch, clipboard status label, settings panel, cleaning duration picker, and clipboard limit picker.
