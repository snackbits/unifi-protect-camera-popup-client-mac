import AppKit
import Carbon.HIToolbox

struct CameraHotkey: Codable, Equatable, Hashable {
    let steps: [HotkeyStep]

    struct HotkeyStep: Codable, Equatable, Hashable {
        let keyCode: UInt16
        let carbonModifiers: UInt32
    }

    var isSequence: Bool { steps.count > 1 }

    init(steps: [HotkeyStep]) {
        self.steps = steps
    }

    init(keyCode: UInt16, carbonModifiers: UInt32) {
        self.steps = [HotkeyStep(keyCode: keyCode, carbonModifiers: carbonModifiers)]
    }

    init?(firstStep event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let relevant = flags.intersection([.command, .option, .control, .shift])
        guard !relevant.isEmpty else { return nil }
        guard !Self.isModifierKey(event.keyCode) else { return nil }

        steps = [
            HotkeyStep(
                keyCode: UInt16(event.keyCode),
                carbonModifiers: Self.carbonModifiers(from: flags)
            )
        ]
    }

    init?(secondStep event: NSEvent) {
        guard !Self.isModifierKey(event.keyCode) else { return nil }
        steps = [HotkeyStep(keyCode: UInt16(event.keyCode), carbonModifiers: 0)]
    }

    /// Sequence shortcuts only care about the second key, not whether ⌘ is still held.
    func normalized() -> CameraHotkey {
        guard isSequence, steps.count >= 2 else { return self }
        return CameraHotkey(steps: [
            steps[0],
            HotkeyStep(keyCode: steps[1].keyCode, carbonModifiers: 0)
        ])
    }

    var displayString: String {
        guard let first = steps.first else { return "" }
        var result = stepDisplayString(for: first)
        if steps.count > 1 {
            result += ", " + Self.keyDisplayName(for: steps[1].keyCode)
        }
        return result
    }

    static func step(from event: NSEvent) -> HotkeyStep {
        HotkeyStep(
            keyCode: UInt16(event.keyCode),
            carbonModifiers: carbonModifiers(
                from: event.modifierFlags.intersection([.command, .option, .control, .shift])
            )
        )
    }

    func matches(step: HotkeyStep, in event: NSEvent) -> Bool {
        Self.step(from: event) == step
    }

    func matchesSequenceSecondKey(in event: NSEvent) -> Bool {
        guard isSequence, steps.count > 1 else { return false }
        return steps[1].keyCode == UInt16(event.keyCode)
    }

    enum CodingKeys: String, CodingKey {
        case steps
        case keyCode
        case carbonModifiers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let steps = try container.decodeIfPresent([HotkeyStep].self, forKey: .steps), !steps.isEmpty {
            self.steps = steps
            return
        }

        let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let carbonModifiers = try container.decode(UInt32.self, forKey: .carbonModifiers)
        steps = [HotkeyStep(keyCode: keyCode, carbonModifiers: carbonModifiers)]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(steps, forKey: .steps)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }

    private func stepDisplayString(for step: HotkeyStep) -> String {
        var parts: [String] = []
        if step.carbonModifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if step.carbonModifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if step.carbonModifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if step.carbonModifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(Self.keyDisplayName(for: step.keyCode))
        return parts.joined()
    }

    private static func isModifierKey(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
             kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
             kVK_CapsLock, kVK_Function:
            return true
        default:
            return false
        }
    }

    private static func keyDisplayName(for keyCode: UInt16) -> String {
        switch Int(keyCode) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_Space: return "Leertaste"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Escape: return "⎋"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            return "Taste \(keyCode)"
        }
    }
}
