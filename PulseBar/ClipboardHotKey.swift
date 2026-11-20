import AppKit
import Carbon

@MainActor
final class ClipboardHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private(set) var isRegistered = false
    private(set) var conflictError: String?
    var onTrigger: (() -> Void)?
    var onTriggerWithApp: ((NSRunningApplication?) -> Void)?

    init(onTrigger: (() -> Void)? = nil, onTriggerWithApp: ((NSRunningApplication?) -> Void)? = nil) {
        self.onTrigger = onTrigger
        self.onTriggerWithApp = onTriggerWithApp
    }

    func register() {
        unregister()
        conflictError = nil

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                guard let theEvent = theEvent, let userData = userData else {
                    return CallNextEventHandler(nextHandler, theEvent)
                }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    theEvent,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr, hotKeyID.signature == OSType(0x50424342), hotKeyID.id == 1 else {
                    return CallNextEventHandler(nextHandler, theEvent)
                }
                let hotKey = Unmanaged<ClipboardHotKey>.fromOpaque(userData).takeUnretainedValue()
                let frontApp = NSWorkspace.shared.frontmostApplication
                DispatchQueue.main.async {
                    if let onTriggerWithApp = hotKey.onTriggerWithApp {
                        onTriggerWithApp(frontApp)
                    } else {
                        hotKey.onTrigger?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )

        guard installStatus == noErr else {
            conflictError = "Could not install shortcut handler (status \(installStatus))."
            isRegistered = false
            return
        }

        let hotKeyID = EventHotKeyID(signature: OSType(0x50424342), id: 1) // 'PBCB'
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            isRegistered = true
            conflictError = nil
        } else {
            isRegistered = false
            conflictError = "Shortcut \u{2318}\u{21e7}V is unavailable or already in use by another app."
            if let handler = eventHandler {
                RemoveEventHandler(handler)
                eventHandler = nil
            }
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
        isRegistered = false
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }
}
