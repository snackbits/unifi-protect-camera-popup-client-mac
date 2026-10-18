import AppCore
import AppKit
import SwiftUI

/// Edits one popup button (template "Button bearbeiten (Sheet)").
struct ActionEditorSheet: View {
    private enum TestState: Equatable {
        case idle
        case running
        case succeeded(Int)
        case failed(String)
    }

    @State private var draft: CameraAction
    private let originalTitle: String
    private let onSave: (CameraAction) -> Void
    private let onDelete: (() -> Void)?
    @State private var test: TestState = .idle
    @Environment(\.dismiss) private var dismiss

    init(action: CameraAction, isNew: Bool, onSave: @escaping (CameraAction) -> Void, onDelete: (() -> Void)?) {
        _draft = State(initialValue: action)
        originalTitle = isNew ? "" : action.trimmedTitle
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(originalTitle.isEmpty ? "Neuer Button" : "Button „\(originalTitle)“")
                .font(.system(size: 15, weight: .bold))
            FormLine(label: "Beschriftung") {
                TokenTextField(placeholder: "z. B. Tür öffnen", text: $draft.title,
                               fontSize: 13, vertical: 5, horizontal: 8, radius: 6)
            }
            FormLine(label: "Symbol") {
                HStack(spacing: 6) {
                    ForEach(ActionIcon.allCases) { icon in
                        let isOn = draft.icon == icon
                        Button { draft.icon = icon } label: {
                            icon.templateIcon.image(size: 16)
                                .foregroundStyle(isOn ? Color.white : Tokens.fg.color)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 7)
                                    .fill(isOn ? Tokens.accent.color : Tokens.btn2.color))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon.label)
                        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                    }
                }
            }
            FormLine(label: "Methode") {
                TokenSegmented(
                    selection: $draft.method,
                    options: CameraAction.Method.allCases.map { (value: $0, title: $0.rawValue) },
                    width: 120
                )
            }
            FormLine(label: "Adresse") {
                TokenTextField(placeholder: "https://…", text: $draft.url,
                               fontSize: 12, vertical: 5, horizontal: 8, radius: 6)
            }
            FormLine(label: "Token") {
                TokenTextField(placeholder: "", text: $draft.bearerToken,
                               fontSize: 12, vertical: 5, horizontal: 8, radius: 6, secure: true)
            }
            FormLine(label: "") {
                Text("Bearer-Token, liegt im Schlüsselbund. Optional.")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.muted.color)
            }
            if let urlWarning {
                FormLine(label: "") {
                    Text(urlWarning).font(.system(size: 11)).foregroundStyle(Color(nsColor: .systemOrange))
                }
            }
            HStack(spacing: 10) {
                Text("Vor dem Ausführen nachfragen").frame(maxWidth: .infinity, alignment: .leading)
                TokenSwitch(isOn: $draft.confirmBeforeRun, label: "Vor dem Ausführen nachfragen")
            }
            testResult
            HStack(spacing: 8) {
                Button(test == .running ? "Teste …" : "Testen", action: runTest)
                    .buttonStyle(FieldButtonStyle(fontSize: 13, vertical: 5, horizontal: 12))
                    .disabled(!draft.isConfigured || test == .running)
                if let onDelete {
                    Button("Entfernen") {
                        onDelete()
                        dismiss()
                    }
                    .buttonStyle(LinkButtonStyle(color: Tokens.muted))
                }
                Spacer()
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(FieldButtonStyle(fontSize: 13, vertical: 5, horizontal: 12))
                    .keyboardShortcut(.cancelAction)
                Button("Sichern") {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(AccentButtonStyle(fontSize: 13, vertical: 5, horizontal: 14))
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isConfigured)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(width: 480)
        .background(Tokens.win.color)
        .foregroundStyle(Tokens.fg.color)
        .font(.system(size: 13))
    }

    @ViewBuilder
    private var testResult: some View {
        switch test {
        case .idle, .running:
            EmptyView()
        case .succeeded(let status):
            resultBox(icon: true, text: "Test erfolgreich · HTTP \(status)", foreground: Tokens.ok.color, background: Tokens.okBg.color)
        case .failed(let message):
            resultBox(icon: false, text: message, foreground: Color(nsColor: .systemOrange),
                      background: Color(nsColor: .systemOrange).opacity(0.12))
        }
    }

    private func resultBox(icon: Bool, text: String, foreground: Color, background: Color) -> some View {
        HStack(spacing: 6) {
            if icon { TemplateIcon.check.image(size: 13) }
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .foregroundStyle(foreground)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7).fill(background))
    }

    private var urlWarning: String? {
        let trimmed = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, draft.requestURL == nil else { return nil }
        return "Bitte eine gültige http:// oder https:// Adresse eintragen."
    }

    private func runTest() {
        let snapshot = draft
        test = .running
        Task {
            do {
                test = .succeeded(try await CameraActionService.trigger(snapshot))
            } catch {
                test = .failed(error.localizedDescription)
            }
        }
    }
}
