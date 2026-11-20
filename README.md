# PulseBar

<div align="center">

**A lightweight, native macOS menu-bar system monitor, Spotlight-style clipboard history manager, and screenshot annotation utility.**

[![Platform](https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue?logo=apple&style=flat-square)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.10-orange?logo=swift&style=flat-square)](https://swift.org)
[![Dependencies](https://img.shields.io/badge/Dependencies-0%20(Native)-success?style=flat-square)]()
[![Privacy](https://img.shields.io/badge/Privacy-100%25%20On--Device-green?style=flat-square)]()

<br />

<img src="photos for readme/clipboard-history-spotlight.png" width="820" alt="PulseBar Spotlight Clipboard History" />

</div>

---

## Overview

PulseBar lives quietly in your macOS menu bar, combining essential daily productivity tools into a single, cohesive, native utility:

- ⚡ **Live System Monitoring**: Network download/upload rates, CPU load, and OS memory pressure directly in the menu bar.
- 📋 **Spotlight-Style Clipboard (`⌘ + Shift + V`)**: Floating multi-category search panel with rich previews, live metadata, and direct auto-paste into active apps.
- 📸 **Screenshot & Annotation (`⌘ + Shift + S`)**: Freeze-frame screen capture with vector arrows, boxes, text, pen, and native MacBook Touch Bar integration.
- ⌨️ **Keyboard Cleaning Mode**: One-click keyboard input lock for safe physical key cleaning without accidental typing.

---

## Features & Visual Walkthrough

### 1. Menu Bar Dashboard & Live Monitoring

Displays real-time physical network bandwidth, CPU utilization, and macOS kernel memory pressure at a glance.

<div align="center">
  <img src="photos for readme/menubar-status-item.png" width="600" alt="Menu Bar Status Item" />
  <p><em>Compact live menu bar indicator with monospaced metrics.</em></p>
</div>

<br />

<div align="center">
  <img src="photos for readme/menubar-dashboard.png" width="420" alt="PulseBar Dashboard" />
  <p><em>Quick dashboard with live metrics cards and feature toggles.</em></p>
</div>

- **Physical Network Accounting**: Samples hardware Wi-Fi and Ethernet interfaces via `SystemConfiguration` (excludes VPN, virtual bridges, and loopback).
- **OS Memory Pressure**: Color-coded RAM indicators follow kernel memory pressure (Normal = Green, Warning = Yellow, Critical = Red), independent of raw caching.
- **Configurable Intervals & Thresholds**: Set sampling rates (500ms to 5s) and custom CPU warning/critical limits.

---

### 2. Spotlight-Style Clipboard History (`⌘ + Shift + V`)

Press **⌘⇧V** anywhere to summon a floating, glass-morphic search panel.

<div align="center">
  <img src="photos for readme/clipboard-history-spotlight.png" width="780" alt="Clipboard History Panel" />
</div>

- **Smart Category Filtering**: Instant 1-click filter pills (`All`, `Text`, `Images`, `Links`, `Files`) with dynamic item counts.
- **Rich Two-Column Inspector**:
  - **Left**: Real-time search field, format badges, relative timestamps, and image thumbnails.
  - **Right**: High-resolution image/text previews, dimensions, file sizes, and metadata.
- **Direct Auto-Paste**: Restores focus to your target application and automatically injects `⌘V` via Accessibility APIs.
- **Keyboard Navigation**: Navigate entries with `↑` / `↓` arrows without losing search field focus; press `↵` to paste, or `Esc` to dismiss.
- **Security & Privacy**: Passwords and transient items (`org.nspasteboard.ConcealedType`) from 1Password, Bitwarden, etc., are strictly ignored. All data stays local.

---

### 3. Screenshot & Annotation Tool (`⌘ + Shift + S`)

Instant screen freeze-frame capture with full-screen selection across all connected displays.

<div align="center">
  <img src="photos for readme/screenshot-tool-card.png" width="480" alt="Screenshot Tool Card" />
</div>

- **Global Hotkey & Touch Bar**: Capture via `⌘⇧S` or directly from the MacBook Touch Bar (native Control Strip interception or dedicated camera button).
- **Interactive Annotation Suite**:
  - ↗️ **Arrows** & 🔲 **Rectangles** with smooth anti-aliased geometry.
  - ✏️ **Freehand Pen** & 🖍️ **Highlighter** marker strokes.
  - 🔤 **Text Labels** with high-contrast background tags.
  - 🎨 Vibrant color presets with full Undo / Redo (`⌘Z` / `⌘⇧Z`).
- **Retina Fidelity**: CoreGraphics composite engine exports lossless PNGs at native 2x display resolution. Copy with **⌘C** or save with **⌘S**.

---

### 4. Keyboard Cleaning Lock Mode

Safely wipe down your MacBook keyboard without triggering unwanted keypresses or phantom text.

<div align="center">
  <img src="photos for readme/dashboard-cleaning-mode.png" width="440" alt="Keyboard Cleaning Active Mode" />
</div>

- **Hardware Keystroke Suppression**: Blocks all keys, modifiers, and media controls while mouse and trackpad remain fully functional.
- **Configurable Timers**: 15s, 30s, 60s, or 120s cleaning sessions.
- **Instant Escape**: Press `Esc` anytime to immediately release the keyboard lock.

---

### 5. Preferences & Customization

Tailor PulseBar to your exact workflow.

<div align="center">
  <img src="photos for readme/preferences-monitoring.png" width="390" alt="Preferences Monitoring" />
  &nbsp;&nbsp;
  <img src="photos for readme/preferences-shortcuts.png" width="390" alt="Preferences Shortcuts" />
</div>

- **Custom Thresholds**: Configure CPU warning and critical alerts.
- **Clipboard Limits**: Set retention capacity (25 to 200 items).
- **Touch Bar Routing**: Redirect the native macOS Touch Bar screenshot button to PulseBar.
- **Auto-Save Folder**: Pick your preferred folder for one-click screenshot saving.
- **Launch at Login**: Native `SMAppService` background launch item.

---

## Keyboard Shortcuts

| Shortcut | Context | Action |
| :--- | :--- | :--- |
| `⌘ + Shift + V` | Global | Open Spotlight Clipboard History |
| `⌘ + Shift + S` | Global | Freeze screen & start Screenshot Selection |
| `↑` / `↓` | Clipboard Panel | Navigate clipboard items |
| `↵` (Return) | Clipboard Panel | Restore & paste selected item |
| `⌘ + C` | Screenshot Overlay | Copy annotated selection to clipboard |
| `⌘ + S` | Screenshot Overlay | Save annotated selection to disk |
| `⌘ + Z` / `⌘ + Shift + Z` | Screenshot Overlay | Undo / Redo annotation |
| `Esc` | Any / Cleaning Mode | Close panel or immediately cancel keyboard lock |

---

## Requirements & Building

- **macOS**: 14.0 (Sonoma) or later (Apple Silicon & Intel Universal)
- **Xcode**: 15.0 or later
- **Dependencies**: **Zero third-party packages** (Built purely with native SwiftUI, AppKit, CoreGraphics, and Carbon)

### Build Instructions

```bash
# Clone the repository
git clone https://github.com/imehedi007/PulseBar-Mac.git
cd PulseBar-Mac

# Open in Xcode
open PulseBar.xcodeproj

# Or build Release directly from terminal
xcodebuild -scheme PulseBar -configuration Release -destination 'platform=macOS' build
```

---

## Privacy & Security

- **100% Local**: PulseBar contains no network analytics, telemetry, or remote servers.
- **Password Manager Protection**: Clipboard entries marked transient or concealed by password managers are automatically ignored.
- **Accessibility Permissions**: Only used locally for direct paste simulation (`CGEvent.postToPid`) and keyboard cleaning event suppression.

---

## License

MIT License.
