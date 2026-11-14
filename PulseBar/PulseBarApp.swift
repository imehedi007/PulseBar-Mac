import SwiftUI
import AppKit

@main
struct PulseBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        controller = MenuBarController()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutdown()
    }
}
