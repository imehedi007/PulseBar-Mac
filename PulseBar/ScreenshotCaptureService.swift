import AppKit
import CoreGraphics

@MainActor
final class ScreenshotCaptureService {
    typealias CGWindowListFunc = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> CGImage?

    static var hasScreenCapturePermission: Bool {
        if #available(macOS 10.15, *) {
            return CGPreflightScreenCaptureAccess()
        }
        return true
    }

    static func requestPermission() {
        if #available(macOS 10.15, *) {
            _ = CGRequestScreenCaptureAccess()
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Captures the specified display or the full desktop union.
    /// Returns the captured CGImage, the screen frame in AppKit coordinates, and the backing scale.
    static func captureDesktop(screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]) -> (image: CGImage, screenFrame: CGRect, scaleFactor: CGFloat)? {
        let frame = screen.frame
        let scale = screen.backingScaleFactor

        // Compute CoreGraphics coordinates (where y=0 is top of primary display)
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? frame.height
        let cgY = primaryScreenHeight - frame.origin.y - frame.height
        let cgRect = CGRect(x: frame.origin.x, y: cgY, width: frame.width, height: frame.height)

        if let image = captureViaCoreGraphics(rect: cgRect) {
            return (image, frame, scale)
        }

        return nil
    }

    /// Captures via dynamic CGWindowListCreateImage (kCGWindowListOptionOnScreenOnly, kCGNullWindowID, kCGWindowImageBestResolution).
    static func captureViaCoreGraphics(rect: CGRect) -> CGImage? {
        guard let handle = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage") else { return nil }
        let fn = unsafeBitCast(handle, to: CGWindowListFunc.self)
        // 1 = kCGWindowListOptionOnScreenOnly, 0 = kCGNullWindowID, 1 = kCGWindowImageBestResolution
        return fn(rect, 1, 0, 1)
    }
}
