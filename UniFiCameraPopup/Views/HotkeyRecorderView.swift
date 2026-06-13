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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Tastenkürzel") {
                HStack(spacing: 8) {
                    Button(action: toggleRecording) {
                        Group {
                            if isRecording {
                                if let recordedFirstStep {
                                    Text("\(stepLabel(recordedFirstStep)), …")
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("Taste drücken…")
                                        .foregroundStyle(.secondary)
                                }
                            } else if let hotkey {
                                Text(hotkey.displayString)
                                    .font(.system(.body, design: .monospaced))
                            } else {
                                Text("Kein Shortcut")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.35), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    if hotkey != nil, !isRecording {
                        Button("Entfernen") {
                            hotkey = nil
                        }
                        .controlSize(.small)
                    }
                }
            }

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
                    Button("Bedienungshilfen öffnen") {
                        AccessibilityHelper.openSettings()
                    }
                    .controlSize(.small)
                }
            } else if isRecording {
                Text(recordingHint)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { refreshAccessibilityAccess() }
        .onDisappear {
            stopRecording()
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
