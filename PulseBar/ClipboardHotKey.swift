import AppKit
import Carbon

@MainActor
final class ClipboardHotKey: GlobalHotKey {
    init(onTrigger: (() -> Void)? = nil, onTriggerWithApp: ((NSRunningApplication?) -> Void)? = nil) {
        super.init(
            keyCode: kVK_ANSI_V,
            modifiers: cmdKey | shiftKey,
            signature: OSType(0x50424342), // 'PBCB'
            id: 1,
            shortcutDisplay: "\u{2318}\u{21e7}V",
            onTrigger: onTrigger,
            onTriggerWithApp: onTriggerWithApp
        )
    }
}
