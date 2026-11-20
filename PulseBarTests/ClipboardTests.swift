import AppKit
import Foundation
import Testing
@testable import PulseBar

@MainActor
struct ClipboardTests {

    private func createTestEnvironment() throws -> (URL, SettingsManager, NSPasteboard) {
        let unique = UUID().uuidString
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("PulseBarTests_Clipboard_\(unique)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let suiteName = "PulseBarTests.Clipboard." + unique
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = SettingsManager(defaults: defaults)

        let pbName = NSPasteboard.Name("PulseBarTests.Pasteboard." + unique)
        let pasteboard = NSPasteboard(name: pbName)
        pasteboard.clearContents()

        return (tempDir, settings, pasteboard)
    }

    private func cleanupTestEnvironment(tempDir: URL, settings: SettingsManager) {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test func textCaptureAndFormatting() throws {
        let (tempDir, settings, pasteboard) = try createTestEnvironment()
        defer { cleanupTestEnvironment(tempDir: tempDir, settings: settings) }

        let clipboard = ClipboardManager(settings: settings, storageDirectory: tempDir, pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("Hello PulseBar\nSecond line of copied text", forType: .string)

        clipboard.pollPasteboard()

        #expect(clipboard.items.count == 1)
        let item = try #require(clipboard.items.first)
        #expect(item.type == .text)
        #expect(item.textValue == "Hello PulseBar\nSecond line of copied text")
        #expect(item.previewTitle == "Hello PulseBar")
        #expect(item.previewSubtitle?.contains("char") == true)
        #expect(item.previewSubtitle?.contains("2 lines") == true)
    }

    @Test func urlCaptureAndFormatting() throws {
        let (tempDir, settings, pasteboard) = try createTestEnvironment()
        defer { cleanupTestEnvironment(tempDir: tempDir, settings: settings) }

        let clipboard = ClipboardManager(settings: settings, storageDirectory: tempDir, pasteboard: pasteboard)
        pasteboard.clearContents()
        let url = try #require(URL(string: "https://github.com/imehedi007/PulseBar"))
        pasteboard.writeObjects([url as NSURL])

        clipboard.pollPasteboard()

        #expect(clipboard.items.count == 1)
        let item = try #require(clipboard.items.first)
        #expect(item.type == .url)
        #expect(item.urlString == "https://github.com/imehedi007/PulseBar")
        #expect(item.previewTitle == "github.com")
        #expect(item.previewSubtitle == "https://github.com/imehedi007/PulseBar")
    }

    @Test func imageCaptureAndDiskStorage() throws {
        let (tempDir, settings, pasteboard) = try createTestEnvironment()
        defer { cleanupTestEnvironment(tempDir: tempDir, settings: settings) }

        let clipboard = ClipboardManager(settings: settings, storageDirectory: tempDir, pasteboard: pasteboard)
        pasteboard.clearContents()

        // Create a 24x24 test NSImage
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()
        NSColor.systemBlue.drawSwatch(in: NSRect(x: 0, y: 0, width: 24, height: 24))
        image.unlockFocus()

        pasteboard.writeObjects([image])

        clipboard.pollPasteboard()

        #expect(clipboard.items.count == 1)
        let item = try #require(clipboard.items.first)
        #expect(item.type == .image)
        #expect(item.imageDimensions != nil)
        #expect(item.imageFileName != nil)

        // Verify image exists on disk
        let imageURL = try #require(clipboard.imageURL(for: item))
        #expect(FileManager.default.fileExists(atPath: imageURL.path))
    }

    @Test func fileReferenceCapture() throws {
        let (tempDir, settings, pasteboard) = try createTestEnvironment()
        defer { cleanupTestEnvironment(tempDir: tempDir, settings: settings) }

        let testFile = tempDir.appendingPathComponent("PulseBarTestDocument.txt")
        try "Test file content".write(to: testFile, atomically: true, encoding: .utf8)

        let clipboard = ClipboardManager(settings: settings, storageDirectory: tempDir, pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.writeObjects([testFile as NSURL])

        clipboard.pollPasteboard()

        #expect(clipboard.items.count == 1)
        let item = try #require(clipboard.items.first)
        #expect(item.type == .file)
        #expect(item.previewTitle == "PulseBarTestDocument.txt")
        #expect(item.filePaths == [testFile.path])
    }

    @Test func deduplicationMovesExistingToTop() throws {
        let (tempDir, settings, pasteboard) = try createTestEnvironment()
        defer { cleanupTestEnvironment(tempDir: tempDir, settings: settings) }

        let clipboard = ClipboardManager(settings: settings, storageDirectory: tempDir, pasteboard: pasteboard)

        // 1. Copy "First"
        pasteboard.clearContents()
        pasteboard.setString("First", forType: .string)
        clipboard.pollPasteboard()

        // 2. Copy "Second"
        pasteboard.clearContents()
        pasteboard.setString("Second", forType: .string)
        clipboard.pollPasteboard()

        #expect(clipboard.items.count == 2)
        #expect(clipboard.items[0].textValue == "Second")
        #expect(clipboard.items[1].textValue == "First")

        // 3. Copy "First" again -> should move to index 0, not create duplicate
        pasteboard.clearContents()
        pasteboard.setString("First", forType: .string)
        clipboard.pollPasteboard()

        #expect(clipboard.items.count == 2)
        #expect(clipboard.items[0].textValue == "First")
        #expect(clipboard.items[1].textValue == "Second")
    }

    @Test func historyLimitPruningAndDiskCleanup() throws {
        let (tempDir, settings, pasteboard) = try createTestEnvironment()
        defer { cleanupTestEnvironment(tempDir: tempDir, settings: settings) }

        settings.update { $0.clipboardLimit = 25 }
        let clipboard = ClipboardManager(settings: settings, storageDirectory: tempDir, pasteboard: pasteboard)

        for i in 1...30 {
            pasteboard.clearContents()
            pasteboard.setString("Entry \(i)", forType: .string)
            clipboard.pollPasteboard()
        }

        #expect(clipboard.items.count == 25)
        #expect(clipboard.items.first?.textValue == "Entry 30")
        #expect(clipboard.items.last?.textValue == "Entry 6")
    }

    @Test func persistenceAcrossLaunches() throws {
        let (tempDir, settings, pasteboard) = try createTestEnvironment()
        defer { cleanupTestEnvironment(tempDir: tempDir, settings: settings) }

        let clipboard1 = ClipboardManager(settings: settings, storageDirectory: tempDir, pasteboard: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("Persisted Text", forType: .string)
        clipboard1.pollPasteboard()
        #expect(clipboard1.items.count == 1)

        // Simulate new app launch with fresh manager pointing to same storage
        let clipboard2 = ClipboardManager(settings: settings, storageDirectory: tempDir, pasteboard: pasteboard)
        #expect(clipboard2.items.count == 1)
        #expect(clipboard2.items.first?.textValue == "Persisted Text")
    }

    @Test func restoreItemToPasteboard() throws {
        let (tempDir, settings, pasteboard) = try createTestEnvironment()
        defer { cleanupTestEnvironment(tempDir: tempDir, settings: settings) }

        let clipboard = ClipboardManager(settings: settings, storageDirectory: tempDir, pasteboard: pasteboard)

        // Capture item
        pasteboard.clearContents()
        pasteboard.setString("Restore Target", forType: .string)
        clipboard.pollPasteboard()
        let item = try #require(clipboard.items.first)

        // Overwrite pasteboard
        pasteboard.clearContents()
        pasteboard.setString("Overwritten", forType: .string)
        #expect(pasteboard.string(forType: .string) == "Overwritten")

        // Restore
        clipboard.restore(item)
        #expect(pasteboard.string(forType: .string) == "Restore Target")
    }

    @Test func deleteItemAndClearAll() throws {
        let (tempDir, settings, pasteboard) = try createTestEnvironment()
        defer { cleanupTestEnvironment(tempDir: tempDir, settings: settings) }

        let clipboard = ClipboardManager(settings: settings, storageDirectory: tempDir, pasteboard: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("Item 1", forType: .string)
        clipboard.pollPasteboard()

        pasteboard.clearContents()
        pasteboard.setString("Item 2", forType: .string)
        clipboard.pollPasteboard()

        #expect(clipboard.items.count == 2)

        // Delete Item 2
        let item2 = clipboard.items[0]
        clipboard.deleteItem(item2)
        #expect(clipboard.items.count == 1)
        #expect(clipboard.items[0].textValue == "Item 1")

        // Clear All
        clipboard.clearAll()
        #expect(clipboard.items.isEmpty)
    }

    @Test func searchFiltering() throws {
        let (tempDir, settings, pasteboard) = try createTestEnvironment()
        defer { cleanupTestEnvironment(tempDir: tempDir, settings: settings) }

        let clipboard = ClipboardManager(settings: settings, storageDirectory: tempDir, pasteboard: pasteboard)
        let controller = ClipboardPanelController(clipboard: clipboard)

        pasteboard.clearContents()
        pasteboard.setString("Swift programming in Xcode", forType: .string)
        clipboard.pollPasteboard()

        pasteboard.clearContents()
        pasteboard.setString("Python machine learning script", forType: .string)
        clipboard.pollPasteboard()

        // Empty search returns all
        controller.searchText = ""
        #expect(controller.filteredItems().count == 2)

        // Search "Swift"
        controller.searchText = "Swift"
        #expect(controller.filteredItems().count == 1)
        #expect(controller.filteredItems().first?.previewTitle.contains("Swift") == true)

        // Case insensitivity
        controller.searchText = "PYTHON"
        #expect(controller.filteredItems().count == 1)
        #expect(controller.filteredItems().first?.previewTitle.contains("Python") == true)

        // Search non-existent
        controller.searchText = "Rust"
        #expect(controller.filteredItems().isEmpty)
    }

    @Test func keyboardNavigationSelection() throws {
        let (tempDir, settings, pasteboard) = try createTestEnvironment()
        defer { cleanupTestEnvironment(tempDir: tempDir, settings: settings) }

        let clipboard = ClipboardManager(settings: settings, storageDirectory: tempDir, pasteboard: pasteboard)
        let controller = ClipboardPanelController(clipboard: clipboard)

        for i in 1...3 {
            pasteboard.clearContents()
            pasteboard.setString("Item \(i)", forType: .string)
            clipboard.pollPasteboard()
        }

        controller.show()
        #expect(controller.selectedItemId == clipboard.items[0].id)

        // Down Arrow
        controller.selectNext()
        #expect(controller.selectedItemId == clipboard.items[1].id)

        // Down Arrow to last
        controller.selectNext()
        #expect(controller.selectedItemId == clipboard.items[2].id)

        // Down Arrow clamped at bottom
        controller.selectNext()
        #expect(controller.selectedItemId == clipboard.items[2].id)

        // Up Arrow
        controller.selectPrevious()
        #expect(controller.selectedItemId == clipboard.items[1].id)

        controller.close()
    }

    @Test func toggleOnOffStopsCaptureImmediately() throws {
        let (tempDir, settings, pasteboard) = try createTestEnvironment()
        defer { cleanupTestEnvironment(tempDir: tempDir, settings: settings) }

        let clipboard = ClipboardManager(settings: settings, storageDirectory: tempDir, pasteboard: pasteboard)
        #expect(clipboard.isEnabled)

        // Turn OFF
        clipboard.setEnabled(false)
        #expect(!clipboard.isEnabled)
        #expect(!settings.preferences.clipboardHistoryEnabled)

        // Attempt copy while OFF
        pasteboard.clearContents()
        pasteboard.setString("Secret content while disabled", forType: .string)
        clipboard.pollPasteboard()

        #expect(clipboard.items.isEmpty)

        // Turn ON again
        clipboard.setEnabled(true)
        #expect(clipboard.isEnabled)
        #expect(settings.preferences.clipboardHistoryEnabled)

        // Copy while ON
        pasteboard.clearContents()
        pasteboard.setString("Allowed content after enabling", forType: .string)
        clipboard.pollPasteboard()

        #expect(clipboard.items.count == 1)
        #expect(clipboard.items.first?.textValue == "Allowed content after enabling")
    }

    @Test func preferencesPersistenceAndNormalization() throws {
        let name = "ClipboardPreferencesTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = SettingsManager(defaults: defaults)
        #expect(settings.preferences.clipboardHistoryEnabled)
        #expect(settings.preferences.clipboardLimit == 50)

        // Update settings
        settings.update {
            $0.clipboardHistoryEnabled = false
            $0.clipboardLimit = 100
        }
        #expect(!settings.preferences.clipboardHistoryEnabled)
        #expect(settings.preferences.clipboardLimit == 100)

        // Invalid limit normalization
        settings.update {
            $0.clipboardLimit = 999
        }
        #expect(settings.preferences.clipboardLimit == 50)

        // Reopen from defaults
        let restored = SettingsManager(defaults: defaults)
        #expect(!restored.preferences.clipboardHistoryEnabled)
        #expect(restored.preferences.clipboardLimit == 50)
    }

    @Test func hotKeyRegistrationAndLifecycle() {
        var triggered = false
        let hotKey = ClipboardHotKey {
            triggered = true
        }

        hotKey.register()
        // Graceful registration check: either succeeds or reports conflict if another app holds it
        if hotKey.isRegistered {
            #expect(hotKey.conflictError == nil)
        } else {
            #expect(hotKey.conflictError != nil)
        }

        // Test triggering callback directly
        hotKey.onTrigger?()
        #expect(triggered)

        hotKey.unregister()
        #expect(!hotKey.isRegistered)
    }

    @Test func imageCacheStorageAndEviction() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("test_cache.png")
        let img = NSImage(size: NSSize(width: 32, height: 32))
        img.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 32, height: 32))
        img.unlockFocus()
        let rep = NSBitmapImageRep(data: try #require(img.tiffRepresentation))
        let png = try #require(rep?.representation(using: .png, properties: [:]))
        try png.write(to: fileURL)

        let cache = ImageCache()
        let loaded1 = cache.image(for: fileURL)
        #expect(loaded1 != nil)

        let loaded2 = cache.image(for: fileURL)
        #expect(loaded2 === loaded1)

        cache.removeImage(for: fileURL)
        cache.clear()
    }

    @Test func selectionUpdateOnItemDeletion() throws {
        let (tempDir, settings, pasteboard) = try createTestEnvironment()
        defer { cleanupTestEnvironment(tempDir: tempDir, settings: settings) }

        let clipboard = ClipboardManager(settings: settings, storageDirectory: tempDir, pasteboard: pasteboard)
        let controller = ClipboardPanelController(clipboard: clipboard)

        for i in 1...3 {
            pasteboard.clearContents()
            pasteboard.setString("Item \(i)", forType: .string)
            clipboard.pollPasteboard()
        }

        // Items are in reverse chronological order: Item 3, Item 2, Item 1
        controller.show()
        #expect(controller.selectedItemId == clipboard.items[0].id) // Item 3

        // Select Item 2 (middle)
        controller.selectNext()
        let item2 = clipboard.items[1]
        #expect(controller.selectedItemId == item2.id)

        // Delete middle item
        controller.deleteItem(item2)
        #expect(clipboard.items.count == 2)
        // Selection advances to the item that took index 1 (Item 1)
        #expect(controller.selectedItemId == clipboard.items[1].id)

        // Delete the remaining last item
        let lastItem = clipboard.items[1]
        controller.deleteItem(lastItem)
        #expect(clipboard.items.count == 1)
        #expect(controller.selectedItemId == clipboard.items[0].id)

        // Delete remaining item
        let remaining = clipboard.items[0]
        controller.deleteItem(remaining)
        #expect(clipboard.items.isEmpty)
        #expect(controller.selectedItemId == nil)
    }

    @Test func targetAppValidation() {
        let settings = SettingsManager()
        let clipboard = ClipboardManager(settings: settings)
        let controller = ClipboardPanelController(clipboard: clipboard)

        // PulseBar itself shouldn't be target app
        controller.targetApp = NSRunningApplication.current
        #expect(controller.targetAppName == nil)
    }

    @Test func nativeFileIconResolution() throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("PulseBarTestFile.swift")
        try "print(1)".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let existingIcon = fileIcon(for: tempFile.path)
        #expect(existingIcon.size.width > 0)

        let virtualIcon = fileIcon(for: "/nonexistent/test.pdf")
        #expect(virtualIcon.size.width > 0)
    }
}
