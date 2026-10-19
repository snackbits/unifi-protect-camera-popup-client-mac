import AppCore
import ProtectKit
import SwiftUI

struct EventRuleEditorContext: Identifiable {
    let id = UUID()
    let rule: EventRule
    let isNew: Bool
}

/// Kameras › „Ereignisse“ (Phase 5, not in the template): built like „Buttons im Popup“.
/// Rows: event 600 (90 wide) · actions `muted`, truncated · link „Ändern“.
struct EventRulesSection: View {
    @Binding var mapping: WebhookMapping
    let camera: ProtectCamera?
    @ObservedObject private var sounds = SoundStore.shared
    @State private var editor: EventRuleEditorContext?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Ereignisse")
            Card(radius: 9) {
                ForEach(mapping.eventRules) { rule in
                    HStack(spacing: 8) {
                        Text(Self.label(rule.kind))
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .frame(width: 90, alignment: .leading)
                        Text(summary(rule))
                            .foregroundStyle(Tokens.muted.color)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Ändern") { editor = EventRuleEditorContext(rule: rule, isNew: false) }
                            .buttonStyle(LinkButtonStyle())
                    }
                    .font(.system(size: 12))
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                    CardDivider()
                }
                if mapping.eventRules.count < EventRule.maxPerCamera {
                    Button("Regel hinzufügen …") {
                        editor = EventRuleEditorContext(rule: EventRule(kind: kinds.first?.rawValue ?? "ring"), isNew: true)
                    }
                    .buttonStyle(LinkButtonStyle())
                    .padding(.vertical, 7)
                    .padding(.horizontal, 12)
                } else {
                    Text("Höchstens \(EventRule.maxPerCamera) Regeln.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.muted.color)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 12)
                }
            }
            Text("Regeln laufen auch ohne Popup und während einer Stummschaltung.")
                .font(.system(size: 11))
                .foregroundStyle(Tokens.muted.color)
        }
        .sheet(item: $editor) { context in
            EventRuleEditorSheet(
                rule: context.rule,
                isNew: context.isNew,
                kinds: kinds,
                sounds: sounds.settings.announcements,
                canPlaySound: TalkbackService.shared.canTalk(mapping),
                knownWithoutSpeaker: camera.map { !$0.hasSpeaker } ?? false,
                onSave: save,
                onDelete: context.isNew ? nil : { delete(context.rule.id) }
            )
        }
    }

    /// What the camera can report, in chip order; without camera data the common ones.
    private var kinds: [TriggerKind] {
        guard let camera else { return [.ring, .person, .vehicle, .animal, .package, .motion] }
        return TriggerKind.displayOrder.filter { camera.supportedTriggers.contains($0) }
    }

    static func label(_ kind: String) -> String {
        TriggerKind(rawValue: kind)?.label ?? kind
    }

    private func summary(_ rule: EventRule) -> String {
        let soundName = rule.soundId.map { id in sounds.settings.announcement(id: id)?.name ?? "Gelöschte Ansage" }
        return EventRuleText.actionSummary(
            webhookAddress: rule.webhook.map { DisplayText.actionAddress($0.url) },
            soundName: soundName,
            delaySeconds: rule.delaySeconds
        )
    }

    private func save(_ rule: EventRule) {
        if let index = mapping.eventRules.firstIndex(where: { $0.id == rule.id }) {
            mapping.eventRules[index] = rule
        } else if mapping.eventRules.count < EventRule.maxPerCamera {
            mapping.eventRules.append(rule)
        }
    }

    private func delete(_ id: UUID) {
        mapping.eventRules.removeAll { $0.id == id }
    }
}

/// Sheet „Regel“: same frame as „Button bearbeiten“ (480 wide, padding 18/20, gap 11, 96 label column).
struct EventRuleEditorSheet: View {
    @State private var draft: EventRule
    @State private var address: String
    @State private var method: CameraAction.Method
    @State private var delayText: String
    @State private var test: WebhookTestState = .idle
    private let isNew: Bool
    private let kinds: [TriggerKind]
    private let sounds: [Announcement]
    private let canPlaySound: Bool
    /// Protect lists the camera and it has no speaker; only then is a kept sound dropped on save
    /// (offline, away without tunnel or just after launch the sound is kept).
    private let knownWithoutSpeaker: Bool
    private let onSave: (EventRule) -> Void
    private let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss

    init(
        rule: EventRule,
        isNew: Bool,
        kinds: [TriggerKind],
        sounds: [Announcement],
        canPlaySound: Bool,
        knownWithoutSpeaker: Bool = false,
        onSave: @escaping (EventRule) -> Void,
        onDelete: (() -> Void)?
    ) {
        _draft = State(initialValue: rule)
        _address = State(initialValue: rule.webhook?.url ?? "")
        _method = State(initialValue: CameraAction.Method(rawValue: rule.webhook?.method ?? "POST") ?? .post)
        _delayText = State(initialValue: rule.delaySeconds > 0 ? String(rule.delaySeconds) : "")
        self.isNew = isNew
        self.kinds = kinds
        self.sounds = sounds
        self.canPlaySound = canPlaySound
        self.knownWithoutSpeaker = knownWithoutSpeaker
        self.onSave = onSave
        self.onDelete = onDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(isNew ? "Neue Regel" : "Regel „\(EventRulesSection.label(draft.kind))“")
                .font(.system(size: 15, weight: .bold))
            FormLine(label: "Ereignis") {
                PopUpField(selection: $draft.kind, options: kindOptions)
            }
            FormLine(label: "Methode") {
                TokenSegmented(
                    selection: $method,
                    options: CameraAction.Method.allCases.map { (value: $0, title: $0.rawValue) },
                    width: 120
                )
            }
            FormLine(label: "Adresse") {
                TokenTextField(placeholder: result.soundId == nil ? "https://…" : "https://… (optional)", text: $address,
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
            if canPlaySound {
                FormLine(label: "Ton") {
                    PopUpField(selection: $draft.soundId, options: soundOptions)
                }
            }
            FormLine(label: "Verzögerung") {
                HStack(spacing: 6) {
                    TokenTextField(placeholder: "0", text: $delayText,
                                   fontSize: 12, vertical: 5, horizontal: 8, radius: 6)
                        .frame(width: 64)
                    Text("Sekunden (0–600)")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.muted.color)
                }
            }
            if let urlWarning {
                FormLine(label: "") {
                    Text(urlWarning).font(.system(size: 11)).foregroundStyle(Color(nsColor: .systemOrange))
                }
            }
            WebhookTestResult(state: test)
            HStack(spacing: 8) {
                Button(test == .running ? "Teste …" : "Testen", action: runTest)
                    .buttonStyle(FieldButtonStyle(fontSize: 13, vertical: 5, horizontal: 12))
                    .disabled(!result.hasWebhook || test == .running)
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
                    onSave(result)
                    dismiss()
                }
                .buttonStyle(AccentButtonStyle(fontSize: 13, vertical: 5, horizontal: 14))
                .keyboardShortcut(.defaultAction)
                .disabled(!result.isConfigured)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 20)
        .frame(width: 480)
        .background(Tokens.win.color)
        .foregroundStyle(Tokens.fg.color)
        .font(.system(size: 13))
    }

    /// The edited rule: empty address = no webhook, delay from the field (0…600). On a camera known
    /// to have no speaker the hidden „Ton“ is dropped (it could never play there).
    private var result: EventRule {
        var rule = draft
        if knownWithoutSpeaker { rule.soundId = nil }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        rule.webhook = trimmed.isEmpty ? nil : EventRuleWebhook(method: method.rawValue, url: trimmed)
        rule.delaySeconds = EventRule.delay(fromText: delayText)
        rule.bearerToken = draft.bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return rule
    }

    private var kindOptions: [(value: String, title: String)] {
        var options = kinds.map { (value: $0.rawValue, title: $0.label) }
        if !options.contains(where: { $0.value == draft.kind }) {
            options.append((value: draft.kind, title: EventRulesSection.label(draft.kind)))
        }
        return options
    }

    private var soundOptions: [(value: UUID?, title: String)] {
        var options: [(value: UUID?, title: String)] = [(value: nil, title: "Kein Ton")]
        options += sounds.map { (value: Optional($0.id), title: $0.name) }
        if let id = draft.soundId, !sounds.contains(where: { $0.id == id }) {
            options.append((value: id, title: "Gelöschte Ansage"))
        }
        return options
    }

    private var urlWarning: String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, result.webhook?.requestURL == nil else { return nil }
        return "Bitte eine gültige http:// oder https:// Adresse eintragen."
    }

    /// Calls the webhook once, now (no delay, no sound).
    private func runTest() {
        let request = EventRuleService.request(for: result)
        test = .running
        Task {
            do {
                test = .succeeded(try await CameraActionService.trigger(request))
            } catch {
                test = .failed(error.localizedDescription)
            }
        }
    }
}
