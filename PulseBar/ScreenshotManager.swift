import AppKit
import Foundation
import Observation

@MainActor @Observable
final class ScreenshotManager {
    private let settings: SettingsManager
    @ObservationIgnored private let hotKey: ScreenshotHotKey
    @ObservationIgnored private let overlay = ScreenshotOverlayController()
    
    private(set) var isCapturing = false
    private(set) var lastSavedURL: URL?
    private(set) var permissionDenied = false

    var isEnabled: Bool {
        settings.preferences.screenshotEnabled
    }

    var shortcutConflictError: String? {
        hotKey.conflictError
    }

    init(settings: SettingsManager) {
        self.settings = settings
        self.hotKey = ScreenshotHotKey()
        
        hotKey.onTrigger = { [weak self] in
            self?.startCapture()
        }

        overlay.onComplete = { [weak self] image, data, isSave in
            guard let self else { return }
            self.isCapturing = false
            
            if isSave {
                _ = self.saveScreenshot(data: data)
                self.copyToClipboard(image: image, data: data, alsoAutoSave: false)
            } else {
                self.copyToClipboard(image: image, data: data, alsoAutoSave: self.settings.preferences.screenshotAutoSave)
            }
        }

        overlay.onCancel = { [weak self] in
            self?.isCapturing = false
        }

        if settings.preferences.screenshotEnabled {
            hotKey.register()
        }
    }

    func setEnabled(_ enabled: Bool) {
        settings.update { $0.screenshotEnabled = enabled }
        if enabled {
            hotKey.register()
        } else {
            hotKey.unregister()
            overlay.close()
            isCapturing = false
        }
    }

    func startCapture() {
        guard isEnabled, !isCapturing else { return }

        guard ScreenshotCaptureService.hasScreenCapturePermission else {
            permissionDenied = true
            ScreenshotCaptureService.requestPermission()
            return
        }
        permissionDenied = false

        guard let capture = ScreenshotCaptureService.captureDesktop() else { return }

        isCapturing = true
        overlay.show(
            capturedImage: capture.image,
            screenFrame: capture.screenFrame,
            scaleFactor: capture.scaleFactor
        )
    }

    func cancelCapture() {
        overlay.close()
        isCapturing = false
    }

    // MARK: - Clipboard & Save
    func copyToClipboard(image: NSImage, data: Data, alsoAutoSave: Bool = false) {
        let pb = NSPasteboard.general
        pb.clearContents()

        // Provide both PNG and TIFF so any application (Slack, Discord, Figma, Finder, etc.) accepts it
        pb.setData(data, forType: .png)
        if let tiff = image.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }

        NSSound(named: "Purr")?.play()

        if alsoAutoSave {
            _ = saveScreenshot(data: data)
        }
    }

    func saveScreenshot(data: Data) -> URL? {
        let directoryURL = screenshotsDirectoryURL()
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let filename = Self.formatFilename(Date())
        let fileURL = directoryURL.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
            lastSavedURL = fileURL
            NSSound(named: "Purr")?.play()
            return fileURL
        } catch {
            return nil
        }
    }

    nonisolated static func formatFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let timestamp = formatter.string(from: date)
        return "Screenshot \(timestamp).png"
    }

    func screenshotsDirectoryURL() -> URL {
        let rawPath = settings.preferences.screenshotSaveDirectory
        let expanded = NSString(string: rawPath).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
    }

    func openScreenshotsFolder() {
        let url = screenshotsDirectoryURL()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    func shutdown() {
        hotKey.unregister()
        overlay.close()
        isCapturing = false
    }
}
