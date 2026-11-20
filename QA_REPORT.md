# PulseBar — Engineering QA & Performance Audit Report

## Native Clipboard History UI/UX & Functionality Refinement — November 20, 2026

Working tree updated; no commit or push. This section supersedes earlier test counts.

- **Debug build including tests**: Built cleanly through Xcode `BuildProject` (0 errors, 0 warnings).
- **Release build**: Built cleanly on Apple Silicon using `xcodebuild -scheme PulseBar -configuration Release` with hardened runtime, validation, and code signing.
- **Final full test suite run**: **46 passed, 0 failed** (45 Swift Testing unit tests across 3 suites, 1 XCUITest UI test), `Test-PulseBar-2026.11.20_00-31-28-+0600.xcresult`.
- **Zero Navigator Issues**: Verified via `XcodeListNavigatorIssues` (0 issues found).
- **Automated test coverage**:
  - **19 Clipboard & Shortcut tests** (`ClipboardTests`): Plain text capture and multiline formatting, web URL scheme and hostname extraction, raw image capturing to local PNG files on disk with dimensions and file size calculation, Finder file references and path formatting, deduplication bringing existing content to top with updated timestamps without creating duplicate entries, configurable history limit pruning with disk cleanup, local JSON and disk persistence across launches, pasteboard restoration across all four content types, deletion of individual items with image removal, Clear All with complete directory cleanup, instant search filtering with case insensitivity, keyboard navigation (up/down clamping), toggle on/off lifecycle (immediate timer cancellation and capture suppression while disabled), preferences persistence and normalization (25, 50, 100, 200 items; default 50), Carbon Global HotKey (`⌘ + Shift + V`) registration, conflict handling and lifecycle, in-memory `ImageCache` storage and eviction, selection update clamping on item deletion, target app validation preventing auto-paste into PulseBar itself, and native file icon resolution.
  - **9 Keyboard Cleaning tests** (`KeyboardCleaningTests`): Activation/deactivation, duration persistence, countdown, timeout, emergency exit, and pointer-event preservation.
  - **17 System Monitor tests** (`PulseBarTests`): CPU deltas, Mach VM memory calculations, network rates, multi-interface delta calculations, units, thresholds, independent colors, lifecycle, and memory pressure transitions.
  - **1 UI Automation test** (`PulseBarUITests`): Menu-bar popover presentation, pause/resume toggle, memory pressure status, keyboard cleaning switch, clipboard history switch, clipboard status label, settings panel, cleaning duration picker, and clipboard limit picker.

### Visual Redesign & Architectural Refinements
1. **Spotlight-Style Two-Column Architecture**:
   - Translucent floating `NSPanel` (700 × 480 pt) with dark `.ultraThinMaterial` blur, 16 pt continuous rounded corners, and subtle elevation shadow.
   - **Left Column (420 pt)**:
     - Prominent top search bar with magnifying glass and quick-clear button, automatically focused upon presentation.
     - Scrollable history list with custom item rows, displaying relative timestamps (e.g., *"Just now"*, *"2m ago"*).
     - Image entries display dedicated thumbnails (115 pt wide × 68 pt high) that strictly preserve aspect ratio with `.scaledToFit()`.
     - File references render native Finder file icons resolved dynamically through `NSWorkspace.shared.icon(forFile:)` / `UTType`.
     - Text and URL entries render distinct system badges with multiline preview snippets and host extraction.
     - Polished hover (`Color.white.opacity(0.06)`) and selected (`Color.accentColor.opacity(0.24)`) states with clear contrast.
     - Quick restore (`arrow.turn.up.left`) and delete (`trash`) action buttons per row.
   - **Right Column (280 pt) — Detail Inspector**:
     - Dynamic inspector displaying rich metadata for the selected item.
     - **Image entries**: Enlarged crisp preview (up to 248 × 180 pt), pixel dimensions (`W × H px`), formatted file size (`KB`/`MB`), capture timestamp, and direct paste/copy action.
     - **Text entries**: Full scrollable text snippet with character count, line count, and copy/paste action.
     - **URL entries**: Clean domain preview, complete URL string, "Open in Default Browser" action, and copy/paste action.
     - **File entries**: Large 48 × 48 pt native Finder file icon, file name, parent folder path, "Reveal in Finder" action, and copy/paste action.
   - **Bottom Footer**:
     - Item count ("X of Y items").
     - Direct paste readiness indicator (showing frontmost target application or accessibility permission requirements).
     - Keyboard shortcut legend (`↑↓ Navigate • ↵ Paste • esc Close`).
     - "Clear All" button with native confirmation dialog.

2. **Keyboard Navigation & Event Handling Solution**:
   - Subclassed `ClipboardPanel: NSPanel` overriding `sendEvent(_ event: NSEvent)`.
   - Intercepts key codes: `53` (`Escape`), `126` (`Up Arrow`), `125` (`Down Arrow`), `36`/`76` (`Return`/`Enter`) directly at the window dispatch level before the first-responder field editor consumes them.
   - Typing immediately routes into the search text field via `super.sendEvent(event)` without losing focus or dropping characters.
   - Arrow keys advance selection up and down without moving the search cursor or producing system beeps.
   - `Enter` immediately restores and pastes the selected item.
   - `Escape` closes the panel immediately.
   - Deleting an entry dynamically updates and clamps selection to the adjacent row index, preventing invalid or orphan selection states.

3. **Clipboard Restoration & Direct Pasting**:
   - Clicking an entry or pressing `Return`/`Enter` restores original content to `NSPasteboard.general`.
   - Before opening the panel, the previously active application is captured (`NSWorkspace.shared.frontmostApplication` and `NSWorkspace.didActivateApplicationNotification`).
   - If macOS Accessibility is granted (`AXIsProcessTrusted() == true`) and target application is external:
     - Focus is restored to the target application (`app.activate()`).
     - After an 80 ms transition window, synthetic `⌘V` keystroke events (`CGEvent`) are posted directly to the application's process queue via `postToPid(targetApp.processIdentifier)`.
     - An on-screen floating toast confirms: `"Pasted into [App]"`.
   - If direct pasting is unavailable (Accessibility permission denied or PulseBar was frontmost):
     - The clipboard content is fully restored to `NSPasteboard.general`.
     - An on-screen floating toast instructs the user: `"Copied to clipboard — Press ⌘V to paste"`.
     - Never falsely claims a paste occurred when only clipboard restoration took place.

4. **Performance & In-Memory Caching**:
   - Introduced `ImageCache` using `NSCache<NSURL, NSImage>` with a 60 MB memory ceiling and 150 item count limit.
   - Eliminates redundant disk reads and image decompression passes during scrolling and inspector updates.
   - When items are deleted or cleared, entries are evicted from cache and deleted from disk.

### Scope of Changes
| File | Changes |
| --- | --- |
| `ClipboardHotKey.swift` | Captured frontmost application on hotkey trigger and forwarded via `onTriggerWithApp` |
| `ClipboardManager.swift` | Forwarded `targetApp` to `onOpenPanelWithApp` during hotkey and menu-bar invocations |
| `ClipboardPanelController.swift` | Subclassed `ClipboardPanel` (`sendEvent` keyboard intercept), two-column Spotlight layout (115px thumbnails + enlarged inspector), native file icons, `ImageCache`, `ClipboardToastController`, and `CGEvent.postToPid` auto-paste with fallback messaging |
| `MenuBarController.swift` | Tracked external application activations, wired `onOpenPanelWithApp` to `clipboardPanel.show(targetApp:)` |
| `SettingsManager.swift` | Relocated `refreshLoginStatus()` onto `Task.detached(priority: .utility)` to prevent blocking main thread |
| `PulseBarApp.swift` | Added `.commandsRemoved()` and `NSApp.mainMenu = nil` to eliminate unnecessary menu accessibility traversals |
| `ClipboardTests.swift` | Added 4 new unit tests covering `ImageCache` lifecycle, deletion selection clamping, target application filtering, and native file icon resolution (19 total clipboard tests) |
| `README.md` | Documented two-column Spotlight interface, image inspector, reliable keyboard navigation, and auto-paste mechanism |
| `QA_REPORT.md` | Documented build results, automated verification, and runtime UI test warning resolution |

### Resolution of Xcode UI Test Runtime Warning

In earlier test runs of `PulseBarUITests.swift` (`testMenuBarPopoverAndPause()`), Xcode reported:
`warning: -[PulseBarUITests.PulseBarUITests testMenuBarPopoverAndPause] : This method should not be called on the main thread as it may lead to UI unresponsiveness.`

- **Offending Operations Identified**:
  1. `SettingsManager.refreshLoginStatus()` was querying `SMAppService.mainApp.status` synchronously on the main thread during popover appearance. `SMAppService.status` executes synchronous IPC with LaunchServices (`launchd` / `LSSharedFileListItemCopyResolvedURL`) and triggers code signature trust evaluations (`SecTrustEvaluateInternal`).
  2. The SwiftUI `Settings` scene by default generates default window menu hierarchies (`NSMainMenu`), which AppKit accessibility inspects when XCTest traverses UI elements.
- **Root-Cause Fixes Applied**:
  1. In `SettingsManager.swift`, moved `SMAppService.mainApp.status` off the main thread into `Task.detached(priority: .utility)`, updating `loginEnabled` and `loginNeedsApproval` back on `MainActor.run`.
  2. In `PulseBarApp.swift`, applied `.commandsRemoved()` to the `Settings` scene and set `NSApp.mainMenu = nil` in `applicationDidFinishLaunching` (appropriate for a dedicated menu-bar accessory application).
- **Verification**:
  - The test suite was re-run via `xcodebuild test` and Xcode test runner.
  - The warning was **completely eliminated** from test execution console logs and build output.
  - Xcode's Issue Navigator confirms **0 issues** across the entire workspace.

---

## Keyboard Cleaning verification — November 19, 2026

Working tree based on `23d7535d3dc196625355300fdfaa89b9b049c4a5`; no commit or push. This section supersedes earlier test counts. No performance benchmarks were repeated.

- Debug build including tests: passed through Xcode BuildProject.
- Release build: passed, `/tmp/PulseBar-Cleaning-Release.log`, code coverage disabled.
- Final full test run: **28 passed, 0 failed** (27 Swift Testing unit tests, 1 UI test), `Test-PulseBar-2026.11.19_23-02-21-+0600.xcresult`.
- New automated coverage checks all four durations, persisted settings, legacy decoding, invalid-duration fallback, countdown progression, expiry, active/inactive symbol selection and immediate state callbacks. Existing activation, deactivation, emergency callback, cancelled timeout, permission failure and pointer-event filtering tests remain passing. Tests inject a blocker and short deadlines; they do not intercept the user's keyboard.
- UI automation verifies the cleaning switch and duration picker alongside existing pressure rows, pause/resume and settings assertions. Live keyboard interception, physical Escape, sleep and full 120-second expiry remain manual checks; no claim of end-to-end hardware verification is made.
