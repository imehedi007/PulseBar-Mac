import AppKit
import Carbon

@MainActor
final class ScreenshotHotKey: GlobalHotKey {
    init(onTrigger: (() -> Void)? = nil) {
        super.init(
            keyCode: kVK_ANSI_S,
            modifiers: cmdKey | shiftKey,
            signature: OSType(0x50425353), // 'PBSS'
            id: 2,
            shortcutDisplay: "\u{2318}\u{21e7}S",
            onTrigger: onTrigger
        )
    }
}
