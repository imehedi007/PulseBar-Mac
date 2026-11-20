import Foundation
import AppKit
import Testing
@testable import PulseBar

struct ScreenshotTests {
    @MainActor @Test func screenshotPreferencesPersistenceAndDefaults() throws {
        let name = "PulseBarScreenshotTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = SettingsManager(defaults: defaults)
        #expect(settings.preferences.screenshotEnabled == true)
        #expect(settings.preferences.screenshotAutoSave == false)
        #expect(settings.preferences.screenshotSaveDirectory == "~/Screenshots")

        settings.update {
            $0.screenshotEnabled = false
            $0.screenshotAutoSave = true
            $0.screenshotSaveDirectory = "~/Downloads/Captures"
        }

        let restored = SettingsManager(defaults: defaults)
        #expect(restored.preferences.screenshotEnabled == false)
        #expect(restored.preferences.screenshotAutoSave == true)
        #expect(restored.preferences.screenshotSaveDirectory == "~/Downloads/Captures")
    }

    @MainActor @Test func screenshotHotKeyLifecycle() {
        let hotKey = ScreenshotHotKey()
        #expect(!hotKey.isRegistered)

        hotKey.register()
        // If Carbon hotkey succeeds, isRegistered is true and conflictError is nil
        if hotKey.isRegistered {
            #expect(hotKey.conflictError == nil)
        }
        hotKey.unregister()
        #expect(!hotKey.isRegistered)
    }

    @Test func annotationToolsAndColors() {
        for tool in AnnotationTool.allCases {
            #expect(!tool.id.isEmpty)
            #expect(!tool.iconName.isEmpty)
        }

        for col in AnnotationColor.allCases {
            #expect(!col.id.isEmpty)
            #expect(col.nsColor.cgColor.alpha > 0)
        }
    }

    @Test func annotationHistoryUndoRedo() {
        let history = ScreenshotAnnotationHistory()
        #expect(!history.canUndo)
        #expect(!history.canRedo)
        #expect(history.items.isEmpty)

        let item1 = AnnotationItem(
            tool: .arrow,
            startPoint: CGPoint(x: 10, y: 10),
            endPoint: CGPoint(x: 50, y: 50),
            color: .red,
            strokeWidth: 3.0
        )
        history.add(item1)
        #expect(history.items.count == 1)
        #expect(history.canUndo)
        #expect(!history.canRedo)

        let item2 = AnnotationItem(
            tool: .rectangle,
            startPoint: CGPoint(x: 20, y: 20),
            endPoint: CGPoint(x: 60, y: 60),
            color: .blue,
            strokeWidth: 2.0
        )
        history.add(item2)
        #expect(history.items.count == 2)

        history.undo()
        #expect(history.items.count == 1)
        #expect(history.items.first?.tool == .arrow)
        #expect(history.canUndo)
        #expect(history.canRedo)

        history.redo()
        #expect(history.items.count == 2)
        #expect(history.items.last?.tool == .rectangle)
        #expect(!history.canRedo)

        history.clear()
        #expect(history.items.isEmpty)
        #expect(history.canUndo)
        history.undo()
        #expect(history.items.count == 2)
    }

    @Test func filenameFormatting() {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 20
        components.hour = 14
        components.minute = 30
        components.second = 45
        let calendar = Calendar(identifier: .gregorian)
        guard let date = calendar.date(from: components) else { return }

        let filename = ScreenshotManager.formatFilename(date)
        #expect(filename == "Screenshot 2026-11-20 at 14.30.45.png")
    }

    @Test func screenshotRendererCompositing() throws {
        // Create a 200x200 test CGImage
        let width = 200
        let height = 200
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ))

        context.setFillColor(NSColor.darkGray.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let sourceCG = try #require(context.makeImage())

        // Annotations inside cropRect (20, 20, 100, 100)
        let crop = CGRect(x: 20, y: 20, width: 100, height: 100)
        let arrow = AnnotationItem(tool: .arrow, startPoint: CGPoint(x: 30, y: 30), endPoint: CGPoint(x: 80, y: 80), color: .red, strokeWidth: 4.0)
        let rect = AnnotationItem(tool: .rectangle, startPoint: CGPoint(x: 40, y: 40), endPoint: CGPoint(x: 90, y: 90), color: .yellow, strokeWidth: 2.0)
        let pen = AnnotationItem(tool: .pen, startPoint: CGPoint(x: 25, y: 25), endPoint: CGPoint(x: 65, y: 65), points: [CGPoint(x: 25, y: 25), CGPoint(x: 45, y: 50), CGPoint(x: 65, y: 65)], color: .green, strokeWidth: 3.0)
        let text = AnnotationItem(tool: .text, startPoint: CGPoint(x: 30, y: 30), endPoint: CGPoint(x: 30, y: 30), text: "PulseBar Note", color: .white, strokeWidth: 1.0)

        let result = ScreenshotRenderer.composite(
            sourceImage: sourceCG,
            cropRect: crop,
            annotations: [arrow, rect, pen, text],
            screenScale: 2.0 // Retina
        )

        let composite = try #require(result)
        #expect(composite.image.size.width == 100)
        #expect(composite.image.size.height == 100)
        #expect(!composite.pngData.isEmpty)

        // Verify PNG magic bytes
        let magic = [UInt8](composite.pngData.prefix(4))
        #expect(magic == [0x89, 0x50, 0x4E, 0x47]) // PNG header
    }

    @MainActor @Test func screenshotSaveAndAutoSaveWorkflow() throws {
        let name = "PulseBarScreenshotSaveTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let settings = SettingsManager(defaults: defaults)
        settings.update {
            $0.screenshotSaveDirectory = tempDir.path
            $0.screenshotAutoSave = true
        }

        let manager = ScreenshotManager(settings: settings)
        #expect(manager.isEnabled)

        // Test saving
        let dummyPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let savedURL = try #require(manager.saveScreenshot(data: dummyPNG))
        #expect(FileManager.default.fileExists(atPath: savedURL.path))
        #expect(manager.lastSavedURL == savedURL)

        // Test clipboard copy
        let image = NSImage(size: NSSize(width: 10, height: 10))
        manager.copyToClipboard(image: image, data: dummyPNG, alsoAutoSave: true)
        let pb = NSPasteboard.general
        #expect(pb.data(forType: .png) == dummyPNG)

        // Toggle disable
        manager.setEnabled(false)
        #expect(!manager.isEnabled)
    }

    @MainActor @Test func overlayKeyboardEventHandling() throws {
        // Create dummy CGImage
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 400,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ))
        let img = try #require(context.makeImage())

        let canvas = ScreenshotCanvasView(
            frame: CGRect(x: 0, y: 0, width: 200, height: 200),
            capturedImage: img,
            screenFrame: CGRect(x: 0, y: 0, width: 200, height: 200),
            scaleFactor: 1.0
        )

        var cancelled = false
        canvas.onCancel = { cancelled = true }

        var copied = false
        canvas.onCopy = { _, _ in copied = true }

        // Esc key (code 53)
        let escEvent = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53
        ))
        #expect(canvas.handleKeyEvent(escEvent) == true)
        #expect(cancelled == true)

        // ⌘C key (code 8)
        let cmdCEvent = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.command], timestamp: 0,
            windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c",
            isARepeat: false, keyCode: 8
        ))
        #expect(canvas.handleKeyEvent(cmdCEvent) == true)
        #expect(copied == true)

        // Tool hotkeys: 'a' for arrow
        let aEvent = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a",
            isARepeat: false, keyCode: 0
        ))
        #expect(canvas.handleKeyEvent(aEvent) == true)
        #expect(canvas.activeTool == .arrow)
    }

    @Test func annotationCoordinateAlignmentWithoutVerticalShift() throws {
        // Desktop: 200 x 200 points, scale = 2.0 (400 x 400 pixels).
        let scale: CGFloat = 2.0
        let desktopBounds = CGRect(x: 0, y: 0, width: 200, height: 200)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let desktopCtx = try #require(CGContext(
            data: nil, width: 400, height: 400, bitsPerComponent: 8, bytesPerRow: 1600,
            space: colorSpace, bitmapInfo: bitmapInfo
        ))

        desktopCtx.setFillColor(NSColor.black.cgColor)
        desktopCtx.fill(CGRect(x: 0, y: 0, width: 400, height: 400))

        // Feature near top of desktop at AppKit point (50, 150) -> x=100, y=300 in desktopCtx
        desktopCtx.setFillColor(NSColor.red.cgColor)
        desktopCtx.fill(CGRect(x: 100, y: 300, width: 20, height: 20))
        let sourceCG = try #require(desktopCtx.makeImage())

        // Selection: y=120..180 (height 60). Feature at y=150 is near the top of this selection.
        let sel = CGRect(x: 20, y: 120, width: 100, height: 60)

        // Draw a green rectangle annotation right over the feature at (50, 150)
        let rect = AnnotationItem(
            tool: .rectangle,
            startPoint: CGPoint(x: 45, y: 145),
            endPoint: CGPoint(x: 65, y: 165),
            color: .green,
            strokeWidth: 2.0
        )

        let result = try #require(ScreenshotRenderer.composite(
            sourceImage: sourceCG,
            selectionRect: sel,
            desktopBounds: desktopBounds,
            annotations: [rect],
            screenScale: scale
        ))

        #expect(result.image.size.width == 100)
        #expect(result.image.size.height == 60)

        // Verify the green rectangle was rendered at the exact feature position, NOT shifted downwards
        let finalCG = try #require(result.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let data = try #require(finalCG.dataProvider?.data)
        let ptr = CFDataGetBytePtr(data)

        // Rect starts at AppKit y=145 inside sel(minY=120, height=60).
        // In compCtx: scaledY = (145 - 120) * 2 = 50.
        // In finalCG (row 0 is top), contextY = 50 is row = targetHeight - 50 = 120 - 50 = 70.
        // Along col = 60 (between x=50 and x=90):
        let targetWidth = 200
        let row = 70
        let col = 60
        let offset = (row * targetWidth + col) * 4

        // Expect green stroke border to be prominent at this location
        #expect(ptr?[offset + 1] ?? 0 > 200)
    }
}
