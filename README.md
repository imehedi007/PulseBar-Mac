# PulseBar

A lightweight, native macOS menu-bar system monitor, Spotlight-style clipboard history manager, and keyboard cleaning lock built with Swift, SwiftUI, AppKit, and Carbon.

```text
↓ 99.2 Mbps ↑ 16.8 Mbps | CPU 34% | RAM 68%
```

---

## Features

### 1. System Monitor
- **Compact Menu-Bar Indicator**: Displays real-time download/upload rates, CPU load, and RAM usage in a single monospaced item without a Dock icon.
- **OS Memory Pressure**: RAM color reflects macOS kernel memory pressure (Normal = Green, Warning = Yellow, Critical = Red, Unknown = Grey), independent of raw utilization.
- **Estimated Headroom**: Displays calculated physical memory headroom alongside OS memory pressure.
- **Physical Network Accounting**: Samples physical Ethernet and Wi-Fi interfaces via `SystemConfiguration`; excludes VPN, bridge, and loopback duplicates.
- **Configurable Refresh Intervals**: 500 ms, 1 s, 2 s, or 5 s sampling rates.
- **Custom Thresholds**: User-defined warning and critical thresholds for CPU.

### 2. Native Clipboard History (Spotlight-Style)
- **Global Hotkey (`⌘ + Shift + V`)**: Instantly invokes a floating Spotlight-style panel from any application.
- **Two-Column Inspector**:
  - **Left Column**: Search bar, relative timestamps, format badges, and 115 px image thumbnails.
  - **Right Column**: Detail inspector with full-resolution previews, metadata (dimensions, file size, character/line counts), and quick action buttons.
- **Multi-Format Support**:
  - **Plain Text**: Line and character counts, multiline preview.
  - **Web URLs**: Hostname extraction, domain badges, direct browser launch.
  - **Images**: PNG disk caching, dimensions, aspect-ratio preservation.
  - **Files**: Native Finder file icons resolved via `NSWorkspace`, parent path navigation, and Finder reveal.
- **Direct Auto-Paste**: Restores focus to the target application and simulates `⌘V` via Accessibility APIs (`CGEvent.postToPid`). Falls back to clipboard copy with an on-screen toast if Accessibility is not granted.
- **Keyboard Navigation**: `↑` / `↓` arrows navigate entries without losing search field focus; `↵` restores and pastes; `Esc` dismisses.
- **In-Memory Caching**: 60 MB `NSCache` image cache prevents redundant disk reads and decoding overhead.
- **Deduplication & History Limit**: Re-copied items jump to the top; configurable history capacity (25, 50, 100, 200 items).
- **Privacy by Design**: All history is stored locally in `~/Library/Application Support/PulseBar/Clipboard/`. Automatically ignores password managers and transient data (`org.nspasteboard.TransientType`, `org.nspasteboard.ConcealedType`).

### 3. Screenshot & Annotation Tool (Lightshot-Inspired)
- **Global Hotkey (`⌘ + Shift + S`) & Touch Bar Integration**: Instant screen freeze-frame capture across all displays with full-screen selection. Supports both the global keyboard shortcut and MacBook Touch Bar (integrates seamlessly with the native Control Strip screenshot button via interception, or as a dedicated custom Control Strip camera button).
- **Custom Region Dragging**: Click and drag to select any desktop area with dimension readout (`width × height px`) and 8-point resize handles.
- **Annotation Suite**:
  - **Arrow**: Sharp directional arrows with proportional arrowheads.
  - **Rectangle**: Clean bounding box with rounded corners.
  - **Pen**: Smooth freehand drawing with anti-aliasing.
  - **Highlighter**: Semi-transparent marker stroke for emphasizing text or UI elements.
  - **Text**: Crisp inline text annotations with high-contrast background tags.
  - **Color Palette & Styling**: Vibrant preset colors (Red, Orange, Yellow, Green, Blue, White, Black).
  - **Undo / Redo (`⌘Z` / `⌘⇧Z`)**: Full annotation history stack.
- **Primary Workflow (`⌘C`)**: Copies the annotated region directly to the system clipboard at full native Retina resolution.
- **Save to Disk (`⌘S`)**: Saves high-resolution PNGs to `~/Screenshots/` with auto-save options.
- **Retina & Display Scaling**: Native backing scale factor preservation for pixel-perfect captures.

### 4. Keyboard Cleaning Mode
- **Session Keyboard Lock**: Disables keystrokes, modifier keys, and media controls to allow safe physical cleaning of your keyboard while keeping the mouse and trackpad active.
- **Emergency Exit**: Press `Escape` or toggle the switch off to restore input immediately.
- **Preset Durations**: Select 15s, 30s, 60s, or 120s countdown timers.
- **Visual Feedback**: Menu-bar keyboard symbol and popover countdown.

---

## Architecture & Code Structure

| File | Subsystem | Responsibility |
| :--- | :--- | :--- |
| `PulseBarApp.swift` | Lifecycle | App entry point, menu-bar accessory configuration, menu removal |
| `MenuBarController.swift` | Coordination | Status item lifecycle, popover management, active app tracking, sleep/wake routing |
| `Monitors.swift` | Metric Readers | Mach CPU/VM statistics, physical interface resolution, rate calculation |
| `MonitoringService.swift` | Sampling Pipeline | Utility-queue background sampling timer, generation checks, state delivery |
| `MenuBarFormatter.swift` | Presentation | NSAttributedString styling, rate and unit conversion, status colors |
| `ContentView.swift` | Popover UI | SwiftUI metrics grid, keyboard cleaning switch, settings panel |
| `SettingsManager.swift` | Persistence | UserDefaults preferences, bounds normalization, SMAppService login item |
| `KeyboardCleaning.swift` | Event Tap | `cgSessionEventTap` keyboard interceptor, timer countdown, emergency exit |
| `ClipboardManager.swift` | Pasteboard Store | Pasteboard polling, format classification, JSON/PNG storage, deduplication |
| `ClipboardHotKey.swift` | Global Shortcut | Carbon Event HotKey registration (`⌘⇧V`), conflict handling |
| `ClipboardPanelController.swift` | Spotlight Window | Floating `NSPanel`, keyboard navigation, auto-paste injection, `ImageCache` |
| `ScreenshotManager.swift` | Screenshot Engine | Screenshot lifecycle, pasteboard copying, automatic and manual disk saving |
| `ScreenshotHotKey.swift` | Global Shortcut | Carbon Event HotKey registration (`⌘⇧S`), conflict handling |
| `ScreenshotCaptureService.swift` | Screen Capture | Native display capture, multi-monitor bounds, Retina scaling, permission checks |
| `ScreenshotOverlayController.swift` | Annotation UI | Multi-display selection overlay, 8 resize handles, Liquid Glass annotation toolbar |
| `ScreenshotModel.swift` | Vector Model | Annotation tools, undo/redo history, Retina-scaled CoreGraphics composite rendering |

---

## Requirements & Building

- **Platform**: macOS 14.0 or later (Apple Silicon & Intel)
- **Dependencies**: None (Uses native SwiftUI, AppKit, Carbon, Mach, SystemConfiguration, ServiceManagement)
- **Xcode**: 16+ / compatible modern toolchain

### Build from Source

1. Open `PulseBar.xcodeproj` in Xcode.
2. Select the **PulseBar** scheme and **My Mac** destination.
3. Select your development team under **Signing & Capabilities**.
4. Press **⌘B** to build or **⌘R** to run.

### Running Automated Tests

Run the full test suite in Xcode via **⌘U**, or via the command line:

```bash
xcodebuild test -scheme PulseBar -destination 'platform=macOS'
```

---

## Permissions & Privacy

- **Accessibility (`AXIsProcessTrusted`)**:
  - Required for direct paste simulation (`CGEvent.postToPid`) in Clipboard History.
  - Required for keyboard event suppression in Keyboard Cleaning.
  - *Standard system monitoring does not require any special permissions.*
- **Zero Network Transmission**: PulseBar does not contain external networking code or telemetry. All metrics and clipboard history remain strictly local on your Mac.
