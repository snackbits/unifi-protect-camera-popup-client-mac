import AppCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Open panel for "MP3 hinzufügen …" (settings and popup).
@MainActor
enum SoundFilePicker {
    static func chooseMP3() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "MP3 hinzufügen"
        panel.prompt = "Hinzufügen"
        panel.allowedContentTypes = [.mp3]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Einstellungen › Ton (docs/design/einstellungen-ton.md).
struct SoundTab: View {
    @ObservedObject private var store = SoundStore.shared
    @ObservedObject private var preview = PreviewPlayer.shared
    @State private var selectedId: UUID?
    @State private var draftKind: Announcement.Kind = .speech
    @State private var draftText = ""
    /// Anna (else the best German voice); read once per appearance of the tab.
    @State private var voice: VoiceChoice.Candidate? = AnnouncementAudio.preferredVoice().map(AnnouncementAudio.candidate)
    @State private var busy = false
    @State private var errorText: String?
    @State private var devices: [AudioInputDevice] = []

    private var selected: Announcement? {
        selectedId.flatMap { store.settings.announcement(id: $0) }
    }

    private var trimmedDraft: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                announcementList
                if let selected {
                    editor(selected)
                }
                deviceCard
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 40)
        }
        .onAppear {
            devices = MicrophoneCapture.inputDevices()
            voice = AnnouncementAudio.preferredVoice().map(AnnouncementAudio.candidate)
            if selected == nil {
                select(store.settings.announcements.first)
            }
            #if DEBUG
            if let sample = SnapshotRenderer.soundTabError { errorText = sample }
            #endif
        }
    }

    // MARK: List

    private var announcementList: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(text: "Ansagen für „Ton abspielen“")
            Card {
                ForEach(store.settings.announcements) { sound in
                    row(sound)
                    CardDivider()
                }
                HStack(spacing: 14) {
                    Button("MP3 hinzufügen …", action: addFile).buttonStyle(LinkButtonStyle())
                    Button("Ansage aus Text …", action: addText).buttonStyle(LinkButtonStyle())
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
            }
            // Without a selection there is no editor card to show the error in.
            if selected == nil, let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ sound: Announcement) -> some View {
        HStack(spacing: 10) {
            Button { togglePreview(sound) } label: {
                ZStack {
                    Circle().fill(Tokens.accSoft.color).frame(width: 22, height: 22)
                    TemplateIcon.play.image(size: 9).foregroundStyle(Tokens.accText.color)
                }
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(preview.playingId == sound.id ? "Probehören beenden" : "Probehören")
            Text(sound.name)
                .fontWeight(.medium)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(Announcement.lengthText(sound.duration))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Tokens.muted.color)
            Text(sound.badge)
                .font(.system(size: 10, weight: .bold))
                .padding(.vertical, 2)
                .padding(.horizontal, 6)
                .foregroundStyle(sound.kind == .file ? Tokens.muted.color : Tokens.accText.color)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(sound.kind == .file ? Tokens.btn2.color : Tokens.accSoft.color))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(sound.id == selectedId ? Tokens.accSoft.color : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { select(sound) }
        .contextMenu {
            Button("Umbenennen …") { rename(sound) }
            Button("Löschen") { delete(sound) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(sound.id == selectedId ? .isSelected : [])
    }

    // MARK: Editor

    private func editor(_ sound: Announcement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("„\(sound.name)“")
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TokenSegmented(
                    selection: $draftKind,
                    options: [(value: Announcement.Kind.file, title: "MP3-Datei"), (value: Announcement.Kind.speech, title: "KI-Stimme")]
                )
            }
            if draftKind == .speech {
                TokenTextField(placeholder: "Text der Ansage", text: $draftText, fontSize: 13, vertical: 5, horizontal: 8, radius: 6)
                    .accessibilityLabel("Text der Ansage")
                HStack(spacing: 8) {
                    Text("Stimme").font(.system(size: 12)).foregroundStyle(Tokens.muted.color)
                    // Only Anna is offered (Phase 5): the field shows the voice and cannot be changed.
                    PopUpField(selection: .constant(0), options: [(value: 0, title: VoiceChoice.fieldLabel(voice))])
                        .disabled(true)
                        .accessibilityLabel("Stimme")
                    Spacer()
                    Button("Anhören") { listen(sound) }
                        .buttonStyle(FieldButtonStyle())
                        .disabled(busy || trimmedDraft.isEmpty)
                    Button("Übernehmen") { apply(sound) }
                        .buttonStyle(AccentButtonStyle(fontSize: 12, vertical: 3, horizontal: 10))
                        .disabled(busy || !canApply(sound))
                }
                Text("Wird auf diesem Mac erzeugt – ohne Internet, ohne Konto.")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.muted.color)
                if let hint = VoiceChoice.hint(voice) {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: .systemOrange))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(spacing: 8) {
                    Text(sound.kind == .file ? "MP3-Datei · \(Announcement.lengthText(sound.duration))" : "Noch keine Datei gewählt.")
                        .foregroundStyle(Tokens.muted.color)
                        .lineLimit(1)
                    Spacer()
                    Button("Datei wählen …") { chooseFile(for: sound) }
                        .buttonStyle(FieldButtonStyle())
                    Button("Anhören") { togglePreview(sound) }
                        .buttonStyle(FieldButtonStyle())
                        .disabled(sound.kind != .file)
                }
                Text("MP3 bis 5 Minuten. Die Datei wird in die App kopiert und bleibt auf diesem Mac.")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.muted.color)
            }
            if let errorText, selected != nil {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Tokens.group.color))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Tokens.accent.color, lineWidth: 1))
    }

    /// New text, or an entry still in another voice (also the bundled recordings): render with Anna.
    private func canApply(_ sound: Announcement) -> Bool {
        guard !trimmedDraft.isEmpty, let voice else { return false }
        return sound.kind != .speech || trimmedDraft != sound.text || sound.voiceIdentifier != voice.identifier
    }

    // MARK: Microphone, volume

    private var deviceCard: some View {
        Card {
            CardRow(title: "Mikrofon") {
                PopUpField(selection: microphone, options: microphoneOptions)
            }
            CardDivider()
            CardRow(title: "Lautstärke Sprechen") {
                VolumeSlider(value: $store.settings.talkVolume, label: "Lautstärke Sprechen")
            }
            CardDivider()
            CardRow(title: "Lautstärke Ansagen") {
                VolumeSlider(value: $store.settings.announcementVolume, label: "Lautstärke Ansagen")
            }
        }
    }

    /// Stored UID if connected, else the system default (also when the stored one is unplugged).
    private var microphone: Binding<String> {
        Binding(
            get: {
                if let uid = store.settings.microphoneUID, devices.contains(where: { $0.uid == uid }) { return uid }
                return MicrophoneCapture.defaultInputDevice()?.uid ?? ""
            },
            set: { store.settings.microphoneUID = $0.isEmpty ? nil : $0 }
        )
    }

    private var microphoneOptions: [(value: String, title: String)] {
        devices.isEmpty ? [(value: "", title: "Kein Mikrofon")] : devices.map { (value: $0.uid, title: $0.name) }
    }

    // MARK: Actions

    private func select(_ sound: Announcement?) {
        selectedId = sound?.id
        errorText = nil
        draftKind = sound?.kind ?? .speech
        draftText = sound?.text ?? ""
    }

    private func addFile() {
        guard let url = SoundFilePicker.chooseMP3() else { return }
        do {
            select(try store.addFile(from: url))
        } catch {
            errorText = message(error)
        }
    }

    private func addText() {
        select(store.addText())
    }

    private func chooseFile(for sound: Announcement) {
        guard let url = SoundFilePicker.chooseMP3() else { return }
        do {
            try store.replaceWithFile(id: sound.id, from: url)
            select(store.settings.announcement(id: sound.id))
        } catch {
            errorText = message(error)
        }
    }

    private func apply(_ sound: Announcement) {
        busy = true
        errorText = nil
        let text = draftText
        Task { @MainActor in
            do {
                try await store.applySpeech(id: sound.id, text: text)
                if selectedId == sound.id { select(store.settings.announcement(id: sound.id)) }
            } catch {
                if selectedId == sound.id { errorText = message(error) }
            }
            busy = false
        }
    }

    private func listen(_ sound: Announcement) {
        busy = true
        errorText = nil
        let text = trimmedDraft
        Task { @MainActor in
            do {
                let buffer = try await store.previewBuffer(text: text)
                preview.play(buffer, id: sound.id)
            } catch {
                if selectedId == sound.id { errorText = message(error) }
            }
            busy = false
        }
    }

    private func togglePreview(_ sound: Announcement) {
        if preview.playingId == sound.id {
            preview.stop()
            return
        }
        guard let url = store.audioURL(for: sound) else {
            errorText = TalkbackError.audioFile("Datei fehlt").errorDescription
            return
        }
        do {
            preview.play(try AnnouncementAudio.load(url), id: sound.id)
        } catch {
            errorText = message(error)
        }
    }

    private func rename(_ sound: Announcement) {
        let alert = NSAlert()
        alert.messageText = "Ansage umbenennen"
        let field = NSTextField(string: sound.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Umbenennen")
        alert.addButton(withTitle: "Abbrechen")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.rename(id: sound.id, to: field.stringValue)
    }

    private func delete(_ sound: Announcement) {
        let alert = NSAlert()
        alert.messageText = "„\(sound.name)“ löschen?"
        alert.informativeText = "Die Ansage verschwindet aus allen Popups."
        alert.addButton(withTitle: "Löschen")
        alert.addButton(withTitle: "Abbrechen")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if preview.playingId == sound.id { preview.stop() }
        store.remove(id: sound.id)
        if selectedId == sound.id {
            select(store.settings.announcements.first)
        }
    }

    private func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
