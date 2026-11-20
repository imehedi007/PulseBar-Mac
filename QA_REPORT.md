# PulseBar — Quality Assurance & Verification Report

## Executive Summary

| Attribute | Specification / Result |
| :--- | :--- |
| **Application** | PulseBar for macOS |
| **Target OS** | macOS 14.0+ (Apple Silicon & Intel) |
| **Build Configurations** | Debug & Release (0 errors, 0 compiler warnings) |
| **Hardened Runtime** | Enabled |
| **App Sandbox** | Disabled (`ENABLE_APP_SANDBOX = NO` for system metric reads & Accessibility event tap) |
| **Automated Test Results** | **60 passed, 0 failed** (57 Swift Testing unit tests + 3 XCUITest UI tests across 5 suites) |
| **Static Analysis / Issues** | 0 warnings, 0 static analysis issues |

---

## Automated Test Coverage Matrix

### 1. Popover UI, Metrics Dashboard & Settings (`PulseBarUITests` — 3 Tests)
- **Status Bar & Popover Lifecycle**: Verified status item existence, opening/closing popover, pausing and resuming live metrics.
- **Card-Based Metrics & Memory Pressure**: Verified real-time CPU, RAM, and Network rate stat cards with dynamic warning badges and tooltip memory breakdown.
- **Grouped Settings & Controls**: Verified collapsible/scrollable settings groups (Monitoring, Tools & History, General), checkBoxes, pickers, CPU threshold steppers, and defaults restoration.
- **Interactive Tool Toggles**: Verified Keyboard Cleaning lock activation, Clipboard History toggling, and Spotlight panel invocation (`⌘⇧V`).

### 2. Screenshot & Annotation Tool (`ScreenshotTests` — 10 Tests)
- **Global Hotkey Lifecycle**: Tested Carbon `⌘ + Shift + S` registration, conflict detection, unregistration, and clean deallocation.
- **Touch Bar Control Strip & Native Button Interception**: Implemented native `DFRFoundation` Control Strip integration, seamless redirection of macOS's native Touch Bar screenshot button to PulseBar (allowing users to position it anywhere in Control Strip settings including the far right edge), dynamic hardware availability detection, lifecycle presence toggling, and action firing.
- **Visual Capture Mode Feedback & Reticle**: Custom high-contrast 28x28 precision reticle cursor with coordinate guide readout (`X: Y:`) and floating HUD instruction banner (`📸 Screenshot Mode • Click and drag to select area • Esc to cancel`).
- **Liquid Glass Floating Toolbar & Circular Handles**: Elevated selection frame with anti-aliased circular pill resize handles, frosted glass toolbar with direct 1-click color palette, hero `⌘C` Copy button, pointing hand (`.pointingHand`) system cursor hover feedback on all options, and default disk save path configured to `~/Screenshots`.
- **Keyboard Shortcuts & Dismissal**: Validated `Esc` cancellation, `⌘C` copy-to-clipboard, and tool hotkey switching (`a`, `p`, `r`, `h`, `t`).
- **Preferences & Persistence**: Validated `screenshotEnabled`, `screenshotAutoSave`, and `screenshotSaveDirectory` defaults and persistence.
- **Annotation History & Undo/Redo**: Verified multi-step item pushing, undo stack preservation, redo restoration, and clear/restore operations.
- **Vector Annotation Tools**: Tested all 5 tools (`Pen`, `Arrow`, `Rectangle`, `Highlight`, `Text`) and preset color palettes.
- **Compositing & Retina Resolution**: Verified native display backing-scale composite rendering (2.0x Retina scaling), crop bounds accuracy, and PNG magic header bytes (`89 50 4E 47`).
- **Coordinate Alignment**: Validated sub-pixel alignment of annotations over captured screen features without vertical inversion or offset displacement.
- **Disk Storage & Naming**: Verified timestamped filename formatting (`Screenshot YYYY-MM-DD at HH.mm.ss.png`) and automatic directory creation.
- **Clipboard Integration**: Validated simultaneous `.png` and `.tiff` pasteboard writing and auto-save triggering.

### 3. Clipboard History & Global Shortcut (`ClipboardTests` — 19 Tests)
- **Content Capture & Formatting**: Verified for plain text, multiline strings, web URLs (hostname extraction), screenshots/images, and Finder file references.
- **Image Storage & Caching**: Validated PNG disk writing to local application support, aspect-ratio preservation, metadata extraction (dimensions, byte size), and in-memory `ImageCache` storage and eviction.
- **Deduplication**: Re-copied identical content updates timestamps and moves entries to the top without creating duplicate records.
- **History Pruning**: Validated automatic boundary enforcement across all supported limits (25, 50, 100, 200 items) and orphaned image file deletion on disk.
- **Persistence & Restoration**: Verified JSON persistence across application launches and accurate restoration back to `NSPasteboard.general` across all four content types.
- **Search Filtering**: Tested real-time case-insensitive filtering across titles, URLs, file paths, and body text.
- **Spotlight Navigation**: Verified clamped up/down arrow navigation, enter-to-paste, selection index adjustment upon item deletion, and target application validation.
- **Global Hotkey Lifecycle**: Tested Carbon `⌘ + Shift + V` registration, conflict handling, and cleanup.

### 4. Keyboard Cleaning Lock (`KeyboardCleaningTests` — 9 Tests)
- **Lifecycle & Activation**: Verified event tap attachment, immediate state notifications, and deactivation.
- **Timer Durations**: Validated duration persistence (15s, 30s, 60s, 120s), legacy preference decoding fallback, and automatic timeout upon deadline expiry.
- **Countdown Progression**: Verified continuous clock countdown decrements and UI state reflection.
- **Safety & Exit**: Tested emergency exit via Escape key (code 53), external cancellation, and graceful handling when accessibility permissions are missing.
- **Event Filtering**: Verified keyboard event suppression (keyDown, keyUp, flagsChanged, systemDefined) while mouse and trackpad pointer events remain untouched.

### 5. System Monitoring Engine & Preferences (`PulseBarTests` — 19 Tests)
- **CPU Calculations**: Verified Mach `HOST_CPU_LOAD_INFO` tick difference calculations, baseline resets on counter anomalies, and core percentage scaling.
- **Memory & Pressure**: Validated Mach `HOST_VM_INFO64` resident calculations, non-purgeable page accounting, categorical OS memory pressure mappings, and independent RAM indicator color states.
- **Estimated Headroom**: Tested available memory percentage estimation bounds and decoupling from OS pressure alerts.
- **Network Rates**: Verified physical interface discovery, byte delta computations, multi-interface aggregation, and reset handling without spurious spikes.
- **Formatting**: Tested decimal bit-rate conversions (bps, Kbps, Mbps, Gbps), gigabyte units, and threshold evaluations.
- **Service Lifecycle**: Verified background timer management, pause/resume state transitions, sleep/wake reconfiguration, and generation check isolation.

---

## Architectural & Safety Verification

1. **Main-Thread Responsiveness**:
   - `SMAppService.mainApp.status` calls execute off the main thread in background tasks, eliminating synchronous LaunchServices IPC overhead during UI presentation.
   - Default main menu bar traversal disabled (`NSApp.mainMenu = nil` and `.commandsRemoved()`), preventing accessibility inspection stalls during XCTest execution.

2. **Memory Pressure Decoupling**:
   - OS memory pressure is reported strictly via `DispatchSource.makeMemoryPressureSource`.
   - Utilization percentages never overwrite or simulate kernel pressure states.

3. **Privacy by Design**:
   - Transient and concealed pasteboard types (e.g., password managers using `org.nspasteboard.TransientType` or `org.nspasteboard.ConcealedType`) are ignored automatically.
   - All clipboard history and image caches remain strictly local on the host system without network transmission.

4. **Event Tap Boundary**:
   - Keyboard interception is session-only and never retained across restarts.
   - Event tap automatically releases on sleep, session switch, app termination, or Escape key invocation.
