# PulseBar — Quality Assurance & Verification Report

## Executive Summary

| Attribute | Specification / Result |
| :--- | :--- |
| **Application** | PulseBar for macOS |
| **Target OS** | macOS 14.0+ (Apple Silicon & Intel) |
| **Build Configurations** | Debug & Release (0 errors, 0 compiler warnings) |
| **Hardened Runtime** | Enabled |
| **App Sandbox** | Disabled (`ENABLE_APP_SANDBOX = NO` for system metric reads & Accessibility event tap) |
| **Automated Test Results** | **46 passed, 0 failed** (45 Swift Testing unit tests across 3 suites, 1 XCUITest UI test) |
| **Static Analysis / Issues** | 0 warnings, 0 static analysis issues |

---

## Automated Test Coverage Matrix

### 1. Clipboard History & Global Shortcut (`ClipboardTests` — 19 Tests)
- **Content Capture & Formatting**: Verified for plain text, multiline strings, web URLs (hostname extraction), screenshots/images, and Finder file references.
- **Image Storage & Caching**: Validated PNG disk writing to local application support, aspect-ratio preservation, metadata extraction (dimensions, byte size), and in-memory `ImageCache` storage and eviction.
- **Deduplication**: Re-copied identical content updates timestamps and moves entries to the top without creating duplicate records.
- **History Pruning**: Validated automatic boundary enforcement across all supported limits (25, 50, 100, 200 items) and orphaned image file deletion on disk.
- **Persistence & Restoration**: Verified JSON persistence across application launches and accurate restoration back to `NSPasteboard.general` across all four content types.
- **Search Filtering**: Tested real-time case-insensitive filtering across titles, URLs, file paths, and body text.
- **Spotlight Navigation**: Verified clamped up/down arrow navigation, enter-to-paste, selection index adjustment upon item deletion, and target application validation.
- **Global Hotkey Lifecycle**: Tested Carbon `⌘ + Shift + V` registration, conflict handling, and cleanup.

### 2. Keyboard Cleaning Lock (`KeyboardCleaningTests` — 9 Tests)
- **Lifecycle & Activation**: Verified event tap attachment, immediate state notifications, and deactivation.
- **Timer Durations**: Validated duration persistence (15s, 30s, 60s, 120s), legacy preference decoding fallback, and automatic timeout upon deadline expiry.
- **Countdown Progression**: Verified continuous clock countdown decrements and UI state reflection.
- **Safety & Exit**: Tested emergency exit via Escape key (code 53), external cancellation, and graceful handling when accessibility permissions are missing.
- **Event Filtering**: Verified keyboard event suppression (keyDown, keyUp, flagsChanged, systemDefined) while mouse and trackpad pointer events remain untouched.

### 3. System Monitoring (`PulseBarTests` — 17 Tests)
- **CPU Calculations**: Verified Mach `HOST_CPU_LOAD_INFO` tick difference calculations, baseline resets on counter anomalies, and core percentage scaling.
- **Memory & Pressure**: Validated Mach `HOST_VM_INFO64` resident calculations, non-purgeable page accounting, categorical OS memory pressure mappings, and independent RAM indicator color states.
- **Estimated Headroom**: Tested available memory percentage estimation bounds and decoupling from OS pressure alerts.
- **Network Rates**: Verified physical interface discovery, byte delta computations, multi-interface aggregation, and reset handling without spurious spikes.
- **Formatting**: Tested decimal bit-rate conversions (bps, Kbps, Mbps, Gbps), gigabyte units, and threshold evaluations.
- **Service Lifecycle**: Verified background timer management, pause/resume state transitions, sleep/wake reconfiguration, and generation check isolation.

### 4. UI Automation (`PulseBarUITests` — 1 Test)
- **Popover Presentation**: Verified status item accessibility, popover display, pause/resume toggle, and metrics grid visibility.
- **Controls & Preferences**: Validated settings panel disclosure, monitoring toggles, cleaning duration selector, clipboard limit picker, and Spotlight search interaction.

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
