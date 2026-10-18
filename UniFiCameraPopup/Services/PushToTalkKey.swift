import Carbon.HIToolbox
import Foundation

/// Space bar as a global hot key (pressed + released) while the pointer is over a popup that can talk.
/// The popup never becomes key, so a local key monitor would not see the space bar.
@MainActor
final class PushToTalkKey {
    static let shared = PushToTalkKey()

    nonisolated static let signature: OSType = 0x5543_5054 // "UCPT"
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onPress: (() -> Void)?
    private var onRelease: (() -> Void)?

    private init() {}

    var isArmed: Bool { hotKey != nil }

    func arm(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
        installHandlerIfNeeded()
        guard hotKey == nil else { return }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(kVK_Space),
            0,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr {
            hotKey = ref
        } else {
            TalkbackLog.write("Leertaste nicht belegbar (\(status))")
        }
    }

    func disarm() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        onPress = nil
        onRelease = nil
    }

    private func handle(pressed: Bool) {
        if pressed { onPress?() } else { onRelease?() }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let error = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &id
                )
                // Other hot keys (camera shortcuts) belong to GlobalHotkeyManager.
                guard error == noErr, id.signature == PushToTalkKey.signature else { return OSStatus(eventNotHandledErr) }
                let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                let key = Unmanaged<PushToTalkKey>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in key.handle(pressed: pressed) }
                return noErr
            },
            types.count,
            &types,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        if status != noErr {
            TalkbackLog.write("Leertasten-Handler fehlt (\(status))")
        }
    }
}
