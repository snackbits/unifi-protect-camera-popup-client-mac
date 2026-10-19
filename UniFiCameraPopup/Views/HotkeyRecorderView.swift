import AppCore
import AppKit
import SwiftUI

struct HotkeyRecorderView: View {
    @Binding var hotkey: CameraHotkey?
    var conflictMessage: String?

    @State private var isRecording = false
    @State private var recordedFirstStep: CameraHotkey.HotkeyStep?
    @State private var monitor: Any?
    @State private var hasAccessibilityAccess = AccessibilityHelper.isTrusted

    private var recordingHint: String {
        if recordedFirstStep != nil {
            return "Dann 1 drücken (⌘ kann gedrückt bleiben). Enter = nur ⌘K. Esc = Abbrechen."
        }
        return "Erst ⌘K, dann 1. Oder nur eine Kombination + Enter. Esc = Abbrechen, ⌫ = Löschen."
    }

    private var needsAccessibilityWarning: Bool {
        hotkey?.isSequence == true && !hasAccessibilityAccess
    }

    private var keyText: String {
        if isRecording {
            if let recordedFirstStep { return "\(stepLabel(recordedFirstStep)), …" }
            return "Taste drücken…"
        }
        return hotkey?.displayString ?? "Kein Shortcut"
    }

    /// Template row: "Tastenkürzel" left, key chip right (12 pt, padding 2/8, radius 5).
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            keyRow
            messages
        }
        .onAppear { refreshAccessibilityAccess() }
        .onDisappear { stopRecording() }
    }

    private var keyRow: some View {
        HStack(spacing: 10) {
            Text("Tastenkürzel").frame(maxWidth: .infinity, alignment: .leading)
            Button(action: toggleRecording) {
                Text(keyText)
                    .font(.system(size: 12))
                    .foregroundStyle(isRecording || hotkey == nil ? Tokens.muted.color : Tokens.fg.color)
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Tokens.field.color))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(isRecording ? Tokens.accent.color : Tokens.chipBorder.color, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tastenkürzel")
            .accessibilityValue(hotkey?.displayString ?? "keins")
        }
    }

    @ViewBuilder
    private var messages: some View {
        if let conflictMessage {
            Label(conflictMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if needsAccessibilityWarning {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "Sequenz-Shortcuts brauchen „Bedienungshilfen“, um im Hintergrund zu funktionieren.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                Button("Bedienungshilfen öffnen") { AccessibilityHelper.openSettings() }
                    .controlSize(.small)
            }
        } else if isRecording {
            Text(recordingHint)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshAccessibilityAccess() {
        hasAccessibilityAccess = AccessibilityHelper.isTrusted
    }

    private func stepLabel(_ step: CameraHotkey.HotkeyStep) -> String {
        CameraHotkey(steps: [step]).displayString
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        recordedFirstStep = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .keyDown {
                if event.keyCode == 53 {
                    stopRecording()
                    return nil
                }
                if event.keyCode == 51 || event.keyCode == 117, recordedFirstStep == nil {
                    hotkey = nil
                    stopRecording()
                    return nil
                }
                if event.keyCode == 36 || event.keyCode == 76, let recordedFirstStep {
                    hotkey = CameraHotkey(steps: [recordedFirstStep])
                    stopRecording()
                    return nil
                }

                if recordedFirstStep == nil {
                    if let first = CameraHotkey(firstStep: event)?.steps.first {
                        recordedFirstStep = first
                    }
                } else if let second = CameraHotkey(secondStep: event)?.steps.first,
                          let first = recordedFirstStep {
                    hotkey = CameraHotkey(steps: [first, second]).normalized()
                    stopRecording()
                }
                return nil
            }
            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        recordedFirstStep = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
