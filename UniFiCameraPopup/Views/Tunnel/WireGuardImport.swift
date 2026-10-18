import AppCore
import AppKit
import ProtectKit
import SwiftUI
import UniformTypeIdentifiers

/// What the last import attempt showed to the user.
enum ImportFeedback: Equatable {
    case imported(endpoint: String, warning: String?)
    case failed(String)

    init(_ result: Result<TunnelImporter.Outcome, TunnelImporter.Failure>) {
        switch result {
        case .success(let outcome): self = .imported(endpoint: outcome.summary.endpoint, warning: outcome.warning)
        case .failure(let failure): self = .failed(failure.localizedDescription)
        }
    }
}

/// File picker, drop and clipboard paths into `ConnectionRouter.importTunnel`.
/// The config text goes to the importer (keychain) only – never to a log or to defaults.
@MainActor
enum WireGuardImport {
    static let menuTitles = ["Datei auswählen …", "Aus Zwischenablage einfügen"]

    /// Runs the entry of `menuTitles` at `index`.
    static func run(menuIndex index: Int) async -> ImportFeedback? {
        index == 0 ? await pickFile() : await importClipboard()
    }

    static func pickFile() async -> ImportFeedback? {
        let panel = NSOpenPanel()
        panel.message = "WireGuard-Datei (.conf) auswählen"
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .plainText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return await importFile(url)
    }

    static func importFile(_ url: URL) async -> ImportFeedback {
        guard let data = readBounded(url) else {
            return .failed("Die Datei lässt sich nicht lesen.")
        }
        // One byte more than allowed was asked for: getting it means the file is too large.
        guard data.count <= WireGuardFile.maxBytes else {
            return .failed(WireGuardFile.Problem.tooLarge.localizedDescription)
        }
        return ImportFeedback(await ConnectionRouter.shared.importTunnel(data: data, fileName: url.lastPathComponent))
    }

    /// At most `maxBytes + 1` bytes of a regular file: never a huge file (or a device, a pipe
    /// that never ends) read into memory just to reject it. nil when it is no regular file or
    /// cannot be read.
    private static func readBounded(_ url: URL) -> Data? {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            // nil at end of file: an empty file (the importer reports it as such).
            return try handle.read(upToCount: WireGuardFile.maxBytes + 1) ?? Data()
        } catch {
            return nil
        }
    }

    static func importClipboard() async -> ImportFeedback {
        var text = NSPasteboard.general.string(forType: .string) ?? ""
        defer { text = "" }
        return ImportFeedback(await ConnectionRouter.shared.importTunnel(text: text))
    }
}

/// „WireGuard-Datei hier ablegen“ (Vorlage Main 6): 74 hoch, Radius 12, 2 pt gestrichelt
/// `dropBorder`, Fläche `accSoft`, Symbol 22 + Abstand 10 + Text 13/600 `accText`.
/// Click opens the file picker; right click also offers the clipboard.
struct WireGuardDropZone: View {
    let onFeedback: (ImportFeedback) -> Void
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 10) {
            TemplateIcon.fileDownload.image(size: 22)
            Text("WireGuard-Datei hier ablegen")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(Tokens.accText.color)
        .frame(maxWidth: .infinity)
        .frame(height: 74)
        .background(RoundedRectangle(cornerRadius: 12).fill(Tokens.accSoft.color))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Tokens.accent.color : Tokens.dropBorder.color,
                              style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture {
            Task { if let feedback = await WireGuardImport.pickFile() { onFeedback(feedback) } }
        }
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in onFeedback(await WireGuardImport.importFile(url)) }
            }
            return true
        }
        .contextMenu {
            ForEach(Array(WireGuardImport.menuTitles.enumerated()), id: \.offset) { index, title in
                Button(title) {
                    Task { if let feedback = await WireGuardImport.run(menuIndex: index) { onFeedback(feedback) } }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Öffnet die Dateiauswahl. Rechtsklick: aus der Zwischenablage einfügen.")
    }
}

/// One line under the drop zone, styled like „Passt. 4 Kameras gefunden.“ (Main 3):
/// 12 pt, Häkchen 14, Abstand 6, `ok`. Hints and errors in system orange (as in Phase 2).
/// Always a single line, so Einrichtung step 6 keeps fitting into 560 × 420.
struct ImportFeedbackView: View {
    let feedback: ImportFeedback

    var body: some View {
        Group {
            switch feedback {
            case .imported(let endpoint, nil):
                HStack(spacing: 6) {
                    TemplateIcon.check.image(size: 14)
                    Text("Passt. Gegenstelle: \(endpoint)")
                }
                .foregroundStyle(Tokens.ok.color)
            case .imported(_, let warning?):
                Text(warning).foregroundStyle(Color(nsColor: .systemOrange))
            case .failed(let message):
                Text(message).foregroundStyle(Color(nsColor: .systemOrange))
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .truncationMode(.middle)
        .help(helpText)
    }

    /// Full text on hover, in case the line is truncated.
    private var helpText: String {
        switch feedback {
        case .imported(let endpoint, let warning): return warning ?? "Gegenstelle: \(endpoint)"
        case .failed(let message): return message
        }
    }
}
