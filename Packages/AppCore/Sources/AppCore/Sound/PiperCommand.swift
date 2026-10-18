import Foundation

/// Where the bundled Piper lives inside the app (filled by piper/scripts/embed.sh).
public struct PiperInstallation: Equatable, Sendable {
    public let executable: URL
    public let espeakData: URL
    /// Folder with the bundled voice (de_DE-thorsten-medium.onnx + .onnx.json).
    public let bundledVoices: URL

    public init(executable: URL, espeakData: URL, bundledVoices: URL) {
        self.executable = executable
        self.espeakData = espeakData
        self.bundledVoices = bundledVoices
    }

    /// `<App>.app/Contents/Helpers/piper/piper` and `<App>.app/Contents/Resources/piper/…`.
    public init(contents: URL) {
        self.init(
            executable: contents.appendingPathComponent("Helpers/piper/piper"),
            espeakData: contents.appendingPathComponent("Resources/piper/espeak-ng-data", isDirectory: true),
            bundledVoices: contents.appendingPathComponent("Resources/piper/voices", isDirectory: true)
        )
    }
}

/// Model and config of one installed voice.
public struct PiperVoiceFiles: Equatable, Sendable {
    public let model: URL
    public let config: URL

    public init(model: URL, config: URL) {
        self.model = model
        self.config = config
    }

    /// `<folder>/<file name of model>` and `<folder>/<file name of config>`.
    public init(voice: PiperVoice, folder: URL) {
        self.init(model: folder.appendingPathComponent(voice.model.fileName),
                  config: folder.appendingPathComponent(voice.config.fileName))
    }
}

/// Command line and input of one Piper run (Process – never linked).
public enum PiperCommand {
    /// Longest text handed to Piper (characters); longer text is cut at a word boundary.
    public static let maxTextLength = 1_000

    public static func arguments(installation: PiperInstallation, files: PiperVoiceFiles, speaker: Int?, output: URL) -> [String] {
        var arguments = [
            "--quiet",
            "--model", files.model.path,
            "--config", files.config.path,
            "--espeak_data", installation.espeakData.path,
            "--output_file", output.path,
        ]
        if let speaker {
            arguments += ["--speaker", String(speaker)]
        }
        return arguments
    }

    /// One line for stdin: line breaks and tabs become spaces, runs of spaces collapse, at most
    /// `maxTextLength` characters; nil when nothing speakable is left.
    public static func input(for text: String) -> String? {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard !words.isEmpty else { return nil }
        var line = ""
        for word in words {
            let next = line.isEmpty ? String(word) : line + " " + word
            if next.count > maxTextLength {
                if line.isEmpty { line = String(next.prefix(maxTextLength)) }
                break
            }
            line = next
        }
        return line + "\n"
    }

    /// Speaker argument only for multi-speaker voices (single-speaker models ignore it anyway).
    public static func speakerArgument(voice: PiperVoice, speaker: Int) -> Int? {
        guard voice.isMultiSpeaker else { return nil }
        return (0..<voice.speakerCount).contains(speaker) ? speaker : voice.defaultSpeaker
    }
}
