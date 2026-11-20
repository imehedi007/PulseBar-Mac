import AppKit
import Carbon

/// Encapsulates Carbon global hotkey registration, event routing, and teardown.
@MainActor
class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    let keyCode: UInt32
    let modifiers: UInt32
    let signature: OSType
    let id: UInt32
    let shortcutDisplay: String

    private(set) var isRegistered = false
    private(set) var conflictError: String?

    var onTrigger: (() -> Void)?
    var onTriggerWithApp: ((NSRunningApplication?) -> Void)?

    init(keyCode: Int,
         modifiers: Int,
         signature: OSType,
         id: UInt32,
         shortcutDisplay: String,
         onTrigger: (() -> Void)? = nil,
         onTriggerWithApp: ((NSRunningApplication?) -> Void)? = nil) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
        self.signature = signature
        self.id = id
        self.shortcutDisplay = shortcutDisplay
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
                let target = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                guard status == noErr,
                      hotKeyID.signature == target.signature,
                      hotKeyID.id == target.id else {
                    return CallNextEventHandler(nextHandler, theEvent)
                }
                let frontApp = NSWorkspace.shared.frontmostApplication
                DispatchQueue.main.async {
                    if let withApp = target.onTriggerWithApp {
                        withApp(frontApp)
                    } else {
                        target.onTrigger?()
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

        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let registerStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
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
            conflictError = "Shortcut \(shortcutDisplay) is unavailable or already in use by another app."
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
