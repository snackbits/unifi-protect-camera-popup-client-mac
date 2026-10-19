import Foundation

/// Audio formats a camera may ask for in its talkback session.
public enum TalkbackCodec: String, Codable, Sendable, CaseIterable {
    case aac
    case opus
    case vorbis

    /// Tolerant mapping of the API's codec name ("aac", "AAC", "libopus", " opus ").
    public init?(wireValue: String) {
        let value = wireValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.contains("opus") {
            self = .opus
        } else if value.contains("aac") {
            self = .aac
        } else if value.contains("vorbis") {
            self = .vorbis
        } else {
            return nil
        }
    }

    /// Rates the system encoders accept (AAC: MPEG-4 rates up to 48 kHz, Opus: its five rates).
    public var supportedSampleRates: Set<Int> {
        switch self {
        case .aac: return [8_000, 11_025, 12_000, 16_000, 22_050, 24_000, 32_000, 44_100, 48_000]
        case .opus: return [8_000, 12_000, 16_000, 24_000, 48_000]
        case .vorbis: return []
        }
    }

    /// Used when the session names no (or a nonsensical) sampling rate.
    public var defaultSampleRate: Int {
        switch self {
        case .aac: return 22_050
        case .opus, .vorbis: return 48_000
        }
    }
}

/// Why talking to a camera did not work. Texts are shown in the popup.
public enum TalkbackError: Error, Equatable, LocalizedError {
    case noSpeaker
    case notConnected
    case unsupportedCodec(String)
    case unsupportedSampleRate(Int)
    case invalidAddress(String)
    case encoder(Int32)
    case network(String)
    case microphoneDenied
    case microphoneUnavailable
    case audioFile(String)
    case fileTooLong
    case speechFailed

    public var errorDescription: String? {
        switch self {
        case .noSpeaker:
            return "Diese Kamera hat keinen Lautsprecher."
        case .notConnected:
            return "Keine Verbindung zu UniFi Protect."
        case .unsupportedCodec(let name):
            return "Die Kamera verlangt das Tonformat „\(name)“ – das kann die App nicht senden."
        case .unsupportedSampleRate(let rate):
            return "Die Kamera verlangt \(rate) Hz – das kann die App nicht senden."
        case .invalidAddress(let raw):
            return "Die Kamera nannte keine gültige Adresse für den Ton („\(raw)“)."
        case .encoder(let status):
            return "Der Ton konnte nicht kodiert werden (Fehler \(status))."
        case .network(let detail):
            return "Senden an die Kamera fehlgeschlagen (\(detail))."
        case .microphoneDenied:
            return "Kein Zugriff aufs Mikrofon. Erlaube ihn unter Systemeinstellungen › Datenschutz & Sicherheit › Mikrofon."
        case .microphoneUnavailable:
            return "Kein Mikrofon gefunden."
        case .audioFile(let detail):
            return "Die Ansage konnte nicht gelesen werden (\(detail))."
        case .fileTooLong:
            return "Die Datei ist länger als 5 Minuten."
        case .speechFailed:
            return "Die Stimme hat keinen Ton erzeugt."
        }
    }
}

/// Where and how talkback audio goes: UDP to the camera, mono, in the camera's codec.
public struct TalkbackTarget: Equatable, Sendable {
    public let host: String
    public let port: UInt16
    public let codec: TalkbackCodec
    public let sampleRate: Int

    public init(host: String, port: UInt16, codec: TalkbackCodec, sampleRate: Int) {
        self.host = host
        self.port = port
        self.codec = codec
        self.sampleRate = sampleRate
    }

    /// Validates what the talkback session returned. Vorbis (Ogg) is not sent by the app.
    public static func make(host: String, port: UInt16, codecName: String, sampleRate: Int) throws -> TalkbackTarget {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty, port > 0 else {
            throw TalkbackError.invalidAddress(trimmedHost.isEmpty ? "leer" : "\(trimmedHost):\(port)")
        }
        guard let codec = TalkbackCodec(wireValue: codecName), codec != .vorbis else {
            throw TalkbackError.unsupportedCodec(codecName.isEmpty ? "unbekannt" : codecName)
        }
        let rate = sampleRate > 0 ? sampleRate : codec.defaultSampleRate
        guard codec.supportedSampleRates.contains(rate) else { throw TalkbackError.unsupportedSampleRate(rate) }
        return TalkbackTarget(host: trimmedHost, port: port, codec: codec, sampleRate: rate)
    }
}
