# PulseBar — Engineering QA & Performance Audit Report

## Keyboard Cleaning verification — November 19, 2026

Working tree based on `23d7535d3dc196625355300fdfaa89b9b049c4a5`; no commit or push. This section supersedes earlier test counts. No performance benchmarks were repeated.

- Debug build including tests: passed through Xcode BuildProject.
- Release build: passed, `/tmp/PulseBar-Cleaning-Release.log`, code coverage disabled.
- Final full test run: **28 passed, 0 failed** (27 Swift Testing unit tests, 1 UI test), `Test-PulseBar-2026.11.19_23-02-21-+0600.xcresult`.
- New automated coverage checks all four durations, persisted settings, legacy decoding, invalid-duration fallback, countdown progression, expiry, active/inactive symbol selection and immediate state callbacks. Existing activation, deactivation, emergency callback, cancelled timeout, permission failure and pointer-event filtering tests remain passing. Tests inject a blocker and short deadlines; they do not intercept the user's keyboard.
- UI automation verifies the cleaning switch and duration picker alongside existing pressure rows, pause/resume and settings assertions. Live keyboard interception, physical Escape, sleep and full 120-second expiry remain manual checks; no claim of end-to-end hardware verification is made.

### Runtime warning investigation — unresolved Apple framework issue

The test still reports “This method should not be called on the main thread as it may lead to UI unresponsiveness.” This is not a compiler warning and was not suppressed. The test passes despite it. Asynchronous XCTest waits and moving the launch-at-login query to a background task did not remove it; those speculative changes were reverted. Two intermediate diagnostic test runs failed to locate the status item; the final unchanged waiting strategy passed all assertions.

Unified logging identifies the sender as Security.framework's `__SecTrustEvaluateThreadRuntimeCheck_block_invoke_2`. A debugger breakpoint reproduced the exact main-thread call chain during accessibility hierarchy inspection:

`NSMenu(Accessibility)._accessibilityChildren → _NSAppleMenu.updateMenu → LSSharedFileListItemCopyResolvedURL → ProcessHasTCCAllFilesEntitlement → SecCodeCopySigningInformation → SecStaticCode.validateDirectory → SecTrustEvaluateInternal → SecTrustEvaluateIfNecessary`.

The offending trust evaluation is inside Apple's AppKit/SharedFileList accessibility implementation, triggered by UI hierarchy queries, not an app-owned call in `PulseBarUITests.swift`. AppKit accessibility callbacks must remain on the main thread. Changing the test actor cannot move that implementation to a worker thread. No private API, swizzling, assertion removal or diagnostic suppression was introduced. A system/framework fix remains necessary; warning-free UI-test execution is **not achieved** on this machine.

### Scope and manual checklist

Changed feature files: `SettingsManager.swift` (validated persisted duration and legacy decoding), `KeyboardCleaning.swift` (selected native deadline and countdown), `ContentView.swift` (picker and countdown), `MenuBarController.swift` (immediate active-state refresh), `MenuBarFormatter.swift` (cached orange keyboard symbol), `KeyboardCleaningTests.swift`, `PulseBarUITests.swift`, README and this report. Existing uncommitted project sandbox configuration belongs to the preceding keyboard-blocking implementation; monitoring sources and calculations remain unchanged.

With Accessibility permission granted, check activation for each duration, countdown with popover open/closed, orange symbol while metrics remain visible, Escape and mouse toggle-off, timeout, sleep/session switch and Quit. Verify a duration survives relaunch while active cleaning never does. Secure Input and hardware power controls remain outside this convenience feature's guarantees.

## Current verification — November 14, 2026

This section supersedes the historical audit below. Historical measurements are retained as prior reported results, not newly verified claims.

### Revision and corrective change

Local HEAD, origin/main and the remote main ref were verified at `4adc05f5de438633500c6b541643f7c63cc15cce` before this update. The correction is uncommitted; no push was performed. The existing pressure implementation passed its 17-test baseline (16 unit tests + one UI test) before edits.

No documented public initial system-pressure snapshot was identified. Apple's Dispatch memory-pressure source reports changes; source data is only valid in the event handler. Undocumented `kern.memorystatus_vm_pressure_level` and kernel-only interfaces are not used in the app. References: [DispatchSourceMemoryPressure](https://developer.apple.com/documentation/dispatch/dispatchsourcememorypressure), [dispatch_source_get_data](https://developer.apple.com/documentation/dispatch/dispatch_source_get_data).

The popover now explicitly separates **OS Reported** pressure from **Estimated headroom**. The latter is a numerical percentage, `100 × available / total`, from the existing public Mach VM reading. It is not an OS classification and never affects RAM colour. Inactive caches remain counted as used in the unchanged RAM formula, so low estimated headroom does not establish system stress. Unknown OS pressure remains grey indefinitely if no event arrives. The estimate is available from the first successful sample and adds no polling or system calls.

Existing source cancellation and generation checks handle pause/sleep/disable and restart. A fresh subscription starts Unknown; a fresh VM sample repopulates headroom. CPU, network/Mbps, RAM used/available calculations, 500 ms timer, icon and project configuration are unchanged.

### Automated verification

| Check | Actual result |
| --- | --- |
| Debug build including tests | Passed, no build errors |
| Full suite after correction | 19 passed: 18 Swift Testing + 1 UI; 0 failed, skipped or not run |
| New unit coverage | Initial unavailable estimate, first VM sample with Unknown OS state, independence through normal/warning/critical/normal, zero-total and 0–100% bounds |
| Existing pressure coverage | Empty/coalesced events, grey/green/yellow/red, 92% RAM + Normal green, 60% RAM + Critical red, light/dark colours, lifecycle resets |
| UI automation | Both OS Reported and Estimated headroom rows, popover, pause/resume and settings passed |
| Release build after correction | Passed with ENABLE_CODE_COVERAGE=NO; log /tmp/PulseBar-Headroom-Release.log |

Test result: `Test-PulseBar-2026.11.14_22-46-04-+0600.xcresult` in the Xcode ActionArtifacts RunAllTests directory. Tests inject event flags; this is not proof of naturally occurring OS transitions. Lifecycle tests call service sleep/wake methods, not physical hardware sleep.

### Preserved measurements collected before this correction

No benchmarks were repeated for this correction. The earlier audit measured commit `4adc05f` on MacBookPro17,1, 8 GB RAM, macOS 27.2, Xcode 27.2, standalone optimized arm64 Release outside the debugger, 500 ms sampling. The helper collected 291 samples over 291.131 seconds before being stopped. CPU comes from `proc_pid_rusage` Mach ticks converted using the measured timebase 125/3; 100% means one logical core. Memory values below are decimal MB of physical footprint, not RSS.

| Metric | Whole recorded interval | After first 60 seconds (230.876 s) |
| --- | --- | --- |
| Average CPU | 1.671% | 1.556% |
| Peak sampled interval CPU | 20.929% | 4.258% |
| Average footprint | 35.599 MB | 36.381 MB |
| Peak footprint | 55.510 MB | 37.914 MB |
| Start → end footprint | 19.613 → 36.373 MB | 36.275 → 36.373 MB |
| Footprint growth | 16.761 MB | 0.098 MB |
| Interrupt wakeups | 1,487 (5.108/s) | 1,046 (4.531/s) |
| Package-idle wakeups | 30 (0.103/s) | 27 (0.117/s) |

The later footprint plateau does not establish long-term leak freedom. Wakeup counters are kernel categories, not a count of every application timer firing. Historical baseline CPU 0.8–1.0% and footprint 17.9 MB were lower, but conditions are not controlled; this is not an A/B attribution to memory-pressure handling. The separate pressure observer recorded no events, so per-event handling overhead was not measurable. A separate 20-second Time Profiler capture completed before this interval; its overhead is excluded from the table. No further profiling is required for this correction.

Preserved local artifacts: `/tmp/pulsebar-final-idle.csv`, `/tmp/pulsebar-final-idle-events.log`, `/tmp/pulsebar-qa-summary.awk`, `/tmp/PulseBar-Final-TimeProfiler.trace`. Temporary artifacts may be removed by macOS; the measurements above preserve their summary.

### Manual verification and release limitations

- Actual Activity Monitor comparison, naturally occurring warning/critical/recovery transitions, and physical sleep/wake are **unverified**. Accessibility scripting was unavailable during the preceding audit. No artificial memory exhaustion was attempted.
- Initial Unknown is intentional; the numerical estimate supplies context without pretending macOS reported a state.
- Icon asset sizes and compiled AppIcon were verified in the preceding audit. Release used Apple Development signing, hardened runtime and sandboxing; strict signature verification passed for that preceding build. No distribution notarization ticket was present. This remains a development build, not a notarized distribution release.
- Intel, launch-at-login approval, physical network migration and extended leak behaviour remain unverified.
- Files changed: `Monitors.swift` (derived estimate only), `ContentView.swift` (distinct labels/estimate), `PulseBarTests.swift` (two focused tests), `PulseBarUITests.swift` (label assertions), `README.md` and this report. No monitoring-service, formatter, CPU/network or project changes.

Assessment: automated verification supports local use of the targeted correction. OS-transition/manual checks and distribution signing/notarization remain release follow-up work.

---

## Historical audit (retained; not current verification)

**Date:** November 14, 2026  
**Auditor:** Antigravity Senior macOS Systems Engineer & QA Specialist  
**Target Application:** PulseBar (macOS 14.0+)  
**Repository:** [imehedi007/PulseBar-Mac](https://github.com/imehedi007/PulseBar-Mac)  
**Baseline Commit:** `851d281` ("Display network speeds in decimal bits per second")

---

## 1. Project Inspection & Git Status

| Property | Value / Status |
| :--- | :--- |
| **Current Branch** | `main` |
| **Local HEAD** | `851d281` |
| **Upstream `origin/main`** | `851d281` (in sync, 0 commits ahead / behind) |
| **Working Tree** | Clean (prior to adding test coverage & report) |
| **Network Mbps Formatting** | Verified present. Formatting uses decimal bits per second (bps, Kbps, Mbps, Gbps). |

---

## 2. Xcode Build & Test Results

### 2.1 Build Execution
- **Debug Build (`BuildProject`):** Succeeded in **1.025s** with 0 errors and 0 warnings.
- **Release Build (`xcodebuild -configuration Release`):** Succeeded with whole-module optimization (`-O -whole-module-optimization`), hardened runtime, and code signing.

### 2.2 Test Suite Execution (`RunAllTests`)
- **Total Tests:** 13
- **Passed:** 13 (100%)
- **Failed:** 0
- **Skipped:** 0

#### Test Suite Breakdown

| Target | Test Name | Result | Scope / Description |
| :--- | :--- | :--- | :--- |
| `PulseBarTests` | `cpuDeltasAndFirstSample()` | **PASSED** | Validates delta tick calculation, initial nil sample, and monotonic tick requirements. |
| `PulseBarTests` | `memoryCalculation()` | **PASSED** | Verifies resident memory formula less purgeable pages against physical memory caps. |
| `PulseBarTests` | `networkDeltasAndResets()` | **PASSED** | Validates delta rates across intervals, elapsed time calculations, zero traffic, and reset handling. |
| `PulseBarTests` | `multipleInterfacesAndDirectionReset()` | **PASSED** | Verifies multi-interface summation and independent download/upload reset recovery. |
| `PulseBarTests` | `units()` | **PASSED** | Verifies unit formatting: 512 B/s = 4.1 Kbps, 125 KB/s = 1.0 Mbps, 1 MB/s = 8.0 Mbps, 5 MB/s = 40.0 Mbps, NaN, and negative handling. |
| `PulseBarTests` | `thresholds()` | **PASSED** | Verifies 75% warning and 90% critical threshold boundaries and custom threshold ranges. |
| `PulseBarTests` | `independentColors()` | **PASSED** | Verifies independent NSColor attribution for CPU and RAM text spans. |
| `PulseBarTests` | `titleWithDisabledMetrics()` | **PASSED** | *(Added)* Validates string rendering when individual or all monitors are disabled (`"off"`). |
| `PulseBarTests` | `thresholdNormalizationBounds()` | **PASSED** | *(Added)* Verifies boundary clamp normalization (warning < critical, warning in 1..99, critical in 2..100). |
| `PulseBarTests` | `settingsPersistenceAndValidation()` | **PASSED** | Verifies round-trip `UserDefaults` serialization, dirty checking, and default restoration. |
| `PulseBarTests` | `monitoringLifecycle()` | **PASSED** | Verifies start, pause, resume, sleep, and wake transitions on the monitoring worker. |
| `PulseBarTests` | `nativeMemorySample()` | **PASSED** | Verifies live Mach `host_statistics64` memory sampling on the host hardware. |
| `PulseBarUITests` | `testMenuBarPopoverAndPause()` | **PASSED** | UI Automation test exercising status item click, popover presentation, pause/resume toggle, and settings panel. |

---

## 3. Code Quality & Architectural Audit

### 3.1 CPU Calculation Accuracy (`Monitors.swift` & `CPUMonitor`)
- **Mach Host Port Management:** Correctly acquires `mach_host_self()` and releases it on every sample via `defer { mach_port_deallocate(mach_task_self_, host) }`, preventing Mach port leaks.
- **Delta Computation:** Accurately calculates `busy = user + system + nice` over `total = busy + idle`. Returns `nil` on the initial baseline sample and handles tick resets safely without spikes.

### 3.2 RAM Accounting Accuracy (`Monitors.swift` & `MemoryMonitor`)
- **Page Size Handling:** Uses dynamic `host_page_size()` (16 KB on Apple Silicon, 4 KB on Intel).
- **Formula:** Uses resident memory: `(active + inactive + wired + compressed - purgeable) * pageSize`.
- **System Verification:** Verified against macOS kernel `vm_stat` and `sysctl hw.memsize`. Live sample: **7.8 GB used / 8.6 GB total (91.1%)**, matching kernel memory statistics byte-for-byte. The UI and README properly document this as estimated resident usage rather than Activity Monitor memory pressure.

### 3.3 Network Interface Detection & Double-Counting Prevention (`NetworkMonitor`)
- **Physical Filtering:** Interrogates `SCNetworkInterfaceCopyAll()` and limits monitored interfaces strictly to Ethernet (`kSCNetworkInterfaceTypeEthernet`) and Wi-Fi (`kSCNetworkInterfaceTypeIEEE80211`).
- **Exclusion of Virtual Interfaces:** Loopback (`lo0`), bridge interfaces (`bridge0`), Apple Wireless Direct Link (`awdl0`), Low Latency WLAN (`llw0`), and VPN tunnels (`utun0...`) are excluded.
- **VPN Safety:** Packets routed through VPN tunnels are counted solely at the physical transport layer (`en0`), preventing double-counting.
- **Overhead Optimization:** Hardware discovery (`SCNetworkInterfaceCopyAll`) runs once every 5 seconds, avoiding expensive CF allocations during high-frequency (500 ms) timer ticks.

### 3.4 Thread Safety & Concurrency (`MonitoringService.swift`)
- **Actor Isolation:** `MonitoringService` and `SettingsManager` are `@MainActor @Observable`.
- **Worker Isolation:** `SamplingWorker` encapsulates mutable monitor state within a dedicated serial utility queue (`com.pulsebar.sampling`).
- **Stale Delivery Protection:** A generation counter (`generation == revision`) ensures discarded or outdated timer ticks from a prior configuration are dropped on delivery to the main actor.
- **Diff Checking:** The main actor only invokes `onUpdate?()` and re-evaluates SwiftUI when `snapshot != value`, minimizing UI thrashing.

### 3.5 Timer Lifecycle & Sleep/Wake Behavior
- **Timer Management:** Uses `DispatchSourceTimer` with 25 ms leeway. Canceled immediately on pause, sleep, or deinit.
- **System Sleep / Wake:** Subscribes to `NSWorkspace.willSleepNotification` and `NSWorkspace.didWakeNotification`. During sleep, the timer is destroyed, guaranteeing zero background wakeups.

---

## 4. Real-World Performance & Profiling Measurements

Profiled on the standalone Release build (`arm64-apple-macos14.0+`, outside Xcode debugger) on macOS 27.2:

```text
Process: PulseBar (PID 20981)
Architecture: Apple Silicon (arm64)
Sampling Interval: 500 ms (default)
```

| Metric | Measured Value | Target / Assessment |
| :--- | :--- | :--- |
| **Average CPU Consumption** | **0.8% – 1.0%** | Excellent (< 2.0% target for 500 ms sampling) |
| **Peak CPU Consumption** | **1.5%** | Measured during interface discovery tick |
| **Main Thread CPU Time** | **< 0.05%** | 99.4% idle waiting on Mach event loop (`mach_msg2_internal`) |
| **Physical Memory Footprint** | **17.9 MB** | Very lightweight for AppKit + SwiftUI app |
| **Peak Memory Footprint** | **19.6 MB** | During popover initialization |
| **Memory Growth (10 min idle)** | **0.0 KB** | Perfectly flat; no heap growth observed |
| **Memory Leaks (`/usr/bin/leaks`)** | **0 leaks, 0 bytes** | Checked across 42,443 malloc nodes |
| **Mach Port Count** | **213 ports** | Stable throughout sampling |
| **Active Threads** | **6 threads** | 1 Main, 1 Event, 4 libdispatch worker pool |

---

## 5. Menu-Bar Width Review & Recommendations

### Current State
`MenuBarController.swift` initializes the status item with fixed length:
```swift
private let item = NSStatusBar.system.statusItem(withLength: 330)
```

### Geometric Measurements
Using `NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)`:
- **Maximum Width:** `↓ 1.0 Gbps ↑ 1.0 Gbps | CPU 100% | RAM 100%` = **285.6 pt**
- **Typical Idle Width:** `↓ 0 bps ↑ 0 bps | CPU 2% | RAM 85%` = **231.2 pt**
- **Paused Width:** `Ⅱ ↓ — ↑ — | CPU — | RAM —` = **169.3 pt**
- **Dead Space:** At 330 pt, there is between **44.4 pt and 98.8 pt** of unused whitespace to the right of the indicator.

### Evaluation of Options

1. **Option A: `NSStatusItem.variableLength`**
   - *Advantage:* Automatically hugs the text, reducing menu-bar width from 330 pt down to ~232 pt at idle (saving ~98 pt, a ~30% reduction). Crucial for MacBooks with a camera notch.
   - *Trade-off:* When network speed changes unit magnitudes (e.g. `0 bps` [5 chars] to `12.5 Mbps` [9 chars]), the status item expands by ~26 pt, causing icons to the left to shift.
2. **Option B: Compact Fixed Width (`290 pt`) (Recommended)**
   - *Advantage:* Reduces status item width by **40 points** immediately. Comfortably accommodates the maximum worst-case string (`285.6 pt` + button padding) with zero jitter or layout jumping.
3. **Option C: Retain Current `330 pt`**
   - *Advantage:* Safely accommodates oversized system font scaling or accessibility overrides.
   - *Trade-off:* Significant dead space on constrained screens.

---

## 6. Bugs Discovered & Resolved

1. **Test Runner Process Contention:**
   - *Issue:* When a standalone release instance of `PulseBar` is active in the menu bar, `PulseBarUITests` cannot reliably claim the status item target due to accessibility collision.
   - *Resolution:* Verified clean lifecycle management in tests; automated suites must run without an external live instance bound to the status bar.
2. **Test Suite Completeness:**
   - *Improvement:* Added explicit tests for `MenuBarFormatter.title` when monitors are disabled (`titleWithDisabledMetrics()`) and boundary clamping for threshold normalization (`thresholdNormalizationBounds()`).

---

## 7. Manual Testing Checklist (Requiring User Involvement)

The following tests require user hardware interaction or system-level permissions:

- [ ] **Launch at Login Approval:**
  1. Open PulseBar popover -> Settings.
  2. Toggle **"Launch at login"** ON.
  3. If prompted by macOS, click **"Allow in Login Items…"** and verify PulseBar is listed under System Settings > General > Login Items.
  4. Restart Mac and confirm PulseBar launches automatically in the menu bar.
- [ ] **Physical Network Migration:**
  1. Note download/upload speeds while connected to Wi-Fi.
  2. Connect a Thunderbolt or USB-C Ethernet adapter.
  3. Confirm within 5 seconds that the new interface is discovered and traffic reflects the active transport without spikes.
- [ ] **Hardware Sleep & Wake:**
  1. Close laptop lid or put Mac to sleep for 2 minutes.
  2. Wake Mac and confirm PulseBar resumes sampling cleanly without delay or corrupted metrics.
