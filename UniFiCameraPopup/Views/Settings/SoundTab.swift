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
    @ObservedObject private var voices = PiperVoiceStore.shared
    @State private var selectedId: UUID?
    @State private var draftKind: Announcement.Kind = .speech
    @State private var draftText = ""
    /// Piper voice + speaker for „Anhören“ and „Übernehmen“ of the selected entry.
    @State private var draftVoice: PiperVoiceRef = .standard
    @State private var busy = false
    @State private var errorText: String?
    @State private var devices: [AudioInputDevice] = []

    private var selected: Announcement? {
        selectedId.flatMap { store.settings.announcement(id: $0) }
    }

    private var trimmedDraft: String {
        draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var draftTooLong: Bool {
        PiperCommand.isTooLong(draftText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                announcementList
                if let selected {
                    editor(selected)
                }
                if !voices.downloadedVoices.isEmpty {
                    downloadedVoicesCard
                }
                deviceCard
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 40)
        }
        .onAppear {
            devices = MicrophoneCapture.inputDevices()
            voices.refresh()
            if selected == nil {
                select(store.settings.announcements.first)
            }
            #if DEBUG
            if let sample = SnapshotRenderer.soundTabError { errorText = sample }
            if let sample = SnapshotRenderer.soundTabVoice { draftVoice = sample }
            if let sample = SnapshotRenderer.soundTabText { draftText = sample }
            #endif
        }
    }

    // MARK: List

    private var announcementList: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(text: "Ansagen für „Ansage abspielen“")
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
                // Piper gets at most PiperCommand.maxTextLength characters: count, and block above it.
                Text(PiperCommand.lengthText(draftText))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(draftTooLong ? Color(nsColor: .systemOrange) : Tokens.muted.color)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text("Stimme").font(.system(size: 12)).foregroundStyle(Tokens.muted.color)
                    PopUpField(selection: voiceSelection, options: voiceOptions)
                        .accessibilityLabel("Stimme")
                    if let voice = draftVoice.resolved?.voice, voice.isMultiSpeaker {
                        PopUpField(selection: speakerSelection, options: speakerOptions(voice))
                            .accessibilityLabel("Sprecher")
                    }
                    Spacer()
                    Button("Anhören") { listen(sound) }
                        .buttonStyle(FieldButtonStyle())
                        .disabled(busy || trimmedDraft.isEmpty || draftTooLong)
                    Button("Übernehmen") { apply(sound) }
                        .buttonStyle(AccentButtonStyle(fontSize: 12, vertical: 3, horizontal: 10))
                        .disabled(busy || !AnnouncementVoice.canApply(sound, text: draftText, selection: draftVoice))
                }
                if let voice = draftVoice.resolved?.voice {
                    if let received = voices.downloads[voice.id] {
                        downloadProgress(voice, received: received)
                    } else if voices.availability(voice) == .notDownloaded {
                        // No voice is bundled: the first use (also of the default Thorsten) downloads it.
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(voice.downloadHint)
                                .font(.system(size: 11))
                                .foregroundStyle(Tokens.muted.color)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("Jetzt laden") { download(voice, for: sound) }
                                .buttonStyle(LinkButtonStyle())
                                .disabled(busy)
                        }
                    } else {
                        Text("Wird auf diesem Mac erzeugt – ohne Internet, ohne Konto.")
                            .font(.system(size: 11))
                            .foregroundStyle(Tokens.muted.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(voice.licenseText)
                        .font(.system(size: 11))
                        .foregroundStyle(Tokens.muted.color)
                        .lineLimit(1)
                }
                if let note = AnnouncementVoice.note(for: sound) {
                    Text(note)
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

    // MARK: Voices

    /// Voice id of the draft; choosing another voice starts with its default speaker.
    private var voiceSelection: Binding<String> {
        Binding(
            get: { draftVoice.voiceId },
            set: { id in
                guard let voice = PiperVoiceCatalog.voice(id: id) else { return }
                draftVoice = PiperVoiceRef(voice: voice)
            }
        )
    }

    private var voiceOptions: [(value: String, title: String)] {
        PiperVoice.menuOrder.map { (value: $0.id, title: $0.menuTitle(voices.availability($0))) }
    }

    private var speakerSelection: Binding<Int> {
        Binding(
            get: { draftVoice.resolved?.speaker ?? 0 },
            set: { draftVoice = PiperVoiceRef(voiceId: draftVoice.voiceId, speaker: $0) }
        )
    }

    private func speakerOptions(_ voice: PiperVoice) -> [(value: Int, title: String)] {
        (0..<voice.speakerCount).map { (value: $0, title: voice.speakerLabel($0) ?? "Sprecher \($0 + 1)") }
    }

    private func downloadProgress(_ voice: PiperVoice, received: Int64) -> some View {
        // Own bar: a linear ProgressView ignores `.tint` on macOS 13 and draws grey in inactive windows.
        let fraction = min(1, max(0, Double(received) / Double(max(voice.downloadSize, 1))))
        return HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.btn2.color)
                Capsule().fill(Tokens.accent.color).frame(width: 120 * fraction)
            }
            .frame(width: 120, height: 5)
            .accessibilityElement()
            .accessibilityLabel("Stimme wird geladen")
            .accessibilityValue("\(Int((fraction * 100).rounded())) Prozent")
            Text(voice.progressText(received: received))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Tokens.muted.color)
                .lineLimit(1)
            Spacer()
            Button("Abbrechen") { voices.cancelDownload(voice) }
                .buttonStyle(LinkButtonStyle())
        }
    }

    /// Downloaded voices with their size and „Entfernen“ (the default voice too – it loads again on use).
    private var downloadedVoicesCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            SectionLabel(text: "Geladene Stimmen")
            Card {
                ForEach(Array(voices.downloadedVoices.enumerated()), id: \.element.id) { index, voice in
                    if index > 0 { CardDivider() }
                    HStack(spacing: 10) {
                        Text(voice.label).frame(maxWidth: .infinity, alignment: .leading)
                        Text(voice.sizeText)
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Tokens.muted.color)
                        Button("Entfernen") { removeVoice(voice) }
                            .buttonStyle(LinkButtonStyle())
                            // Piper is speaking with it right now: wait until that render is done.
                            .disabled(voices.isRendering(with: voice))
                            .help(voices.isRendering(with: voice) ? "Die Stimme spricht gerade – gleich wieder möglich." : "")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                }
            }
        }
    }

    private func removeVoice(_ voice: PiperVoice) {
        let alert = NSAlert()
        alert.messageText = "„\(voice.label)“ entfernen?"
        alert.informativeText = "Ansagen mit dieser Stimme spielen weiter. Zum Anhören oder neu Erzeugen wird sie wieder geladen (\(voice.sizeText))."
        alert.addButton(withTitle: "Entfernen")
        alert.addButton(withTitle: "Abbrechen")
        guard alert.runModal() == .alertFirstButtonReturn, !voices.isRendering(with: voice) else { return }
        voices.remove(voice)
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
        draftVoice = sound.map(AnnouncementVoice.initialSelection) ?? .standard
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
        let voice = draftVoice
        Task { @MainActor in
            do {
                try await store.applySpeech(id: sound.id, text: text, voice: voice)
                if selectedId == sound.id { select(store.settings.announcement(id: sound.id)) }
            } catch {
                if selectedId == sound.id { errorText = message(error) }
            }
            busy = false
        }
    }

    /// „Jetzt laden“: the voice's download without speaking (Anhören/Übernehmen would load it too).
    private func download(_ voice: PiperVoice, for sound: Announcement) {
        errorText = nil
        Task { @MainActor in
            do {
                _ = try await voices.ensure(voice)
            } catch {
                if selectedId == sound.id { errorText = message(error) }
            }
        }
    }

    private func listen(_ sound: Announcement) {
        busy = true
        errorText = nil
        let text = trimmedDraft
        let voice = draftVoice
        Task { @MainActor in
            do {
                let buffer = try await store.previewBuffer(text: text, voice: voice)
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

    /// nil for a cancelled download (the user pressed „Abbrechen“ – nothing to report).
    private func message(_ error: Error) -> String? {
        if error is CancellationError { return nil }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
