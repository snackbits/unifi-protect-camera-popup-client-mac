import Foundation

/// Quality level of a Piper voice (`voices.json` › `quality`).
public enum PiperQuality: String, Codable, Sendable, CaseIterable {
    case xLow = "x_low"
    case low
    case medium
    case high

    /// „sehr niedrig“ … „hoch“ – second part of „Thorsten · mittel“.
    public var label: String {
        switch self {
        case .xLow: return "sehr niedrig"
        case .low: return "niedrig"
        case .medium: return "mittel"
        case .high: return "hoch"
        }
    }
}

/// License of a voice's training data (from its MODEL_CARD at `PiperVoiceCatalog.revision`).
public struct VoiceLicense: Equatable, Sendable {
    /// „CC0 1.0“, „CC BY 4.0“ …
    public let name: String
    /// Dataset the voice was trained on.
    public let dataset: String
    public let url: String
    /// Commercial use and redistribution allowed – otherwise the voice is not offered.
    public let allowsRedistribution: Bool
    /// Shown in „Über“ when the license asks for attribution.
    public let attribution: String?

    public static let thorstenCC0 = VoiceLicense(
        name: "CC0 1.0", dataset: "Thorsten-Voice (Thorsten Müller)",
        url: "https://github.com/thorstenMueller/Thorsten-Voice", allowsRedistribution: true, attribution: nil)
    public static let kerstinCC0 = VoiceLicense(
        name: "CC0 1.0", dataset: "dataset-voice-kerstin (Rhasspy)",
        url: "https://github.com/rhasspy/dataset-voice-kerstin", allowsRedistribution: true, attribution: nil)
    public static let mailabs = VoiceLicense(
        name: "M-AILABS-Lizenz (BSD-artig, kommerziell erlaubt)", dataset: "M-AILABS Speech Dataset",
        url: "https://www.caito.de/2019/01/03/the-m-ailabs-speech-dataset/", allowsRedistribution: true,
        attribution: "Copyright (c) 2017-2019 by the original creators @ M-AILABS")
    public static let pavoqueNC = VoiceLicense(
        name: "CC BY-NC-SA 4.0", dataset: "PAVOQUE (MaryTTS)",
        url: "https://github.com/marytts/pavoque-data", allowsRedistribution: false, attribution: nil)
}

/// One downloadable file of a voice, pinned by size and SHA-256.
public struct VoiceFile: Equatable, Sendable {
    /// Path inside the Hugging Face repository `rhasspy/piper-voices`.
    public let path: String
    public let size: Int64
    public let sha256: String

    public init(path: String, size: Int64, sha256: String) {
        self.path = path
        self.size = size
        self.sha256 = sha256
    }

    public var fileName: String { (path as NSString).lastPathComponent }

    /// Fixed revision – never `main`.
    public var url: URL {
        URL(string: "https://huggingface.co/rhasspy/piper-voices/resolve/\(PiperVoiceCatalog.revision)/\(path)")!
    }
}

/// One German Piper voice (model + config) from `rhasspy/piper-voices`.
public struct PiperVoice: Equatable, Identifiable, Sendable {
    /// `voices.json` key, e.g. „de_DE-thorsten-medium“.
    public let id: String
    public let name: String
    public let quality: PiperQuality
    public let sampleRate: Int
    public let model: VoiceFile
    public let config: VoiceFile
    public let license: VoiceLicense
    /// Speaker labels by index (Piper `--speaker`); empty = numbered „Sprecher 1 …“.
    public let speakerNames: [String]
    public let speakerCount: Int
    public let defaultSpeaker: Int

    public init(id: String, name: String, quality: PiperQuality, sampleRate: Int, model: VoiceFile, config: VoiceFile,
                license: VoiceLicense, speakerNames: [String] = [], speakerCount: Int? = nil, defaultSpeaker: Int = 0) {
        self.id = id
        self.name = name
        self.quality = quality
        self.sampleRate = sampleRate
        self.model = model
        self.config = config
        self.license = license
        self.speakerNames = speakerNames
        self.speakerCount = speakerCount ?? max(1, speakerNames.count)
        self.defaultSpeaker = defaultSpeaker
    }

    public var isMultiSpeaker: Bool { speakerCount > 1 }
    /// Model + config.
    public var downloadSize: Int64 { model.size + config.size }
    /// „Thorsten · mittel“.
    public var label: String { "\(name) · \(quality.label)" }

    /// „neutral“ / „Sprecher 12“; nil for single-speaker voices.
    public func speakerLabel(_ index: Int) -> String? {
        guard isMultiSpeaker, (0..<speakerCount).contains(index) else { return nil }
        return index < speakerNames.count ? speakerNames[index] : "Sprecher \(index + 1)"
    }
}

/// Every German voice of `rhasspy/piper-voices` at `revision` (de_DE only – no de_AT/de_CH exists).
/// Sizes and SHA-256 of the models are the Git-LFS object ids; the configs were hashed at the revision.
public enum PiperVoiceCatalog {
    public static let revision = "c10ece1aade47bb51c153c893d14e5bf8e5b7117"
    /// The voice new announcements use. Not shipped in the app (that kept app.zip under GitHub's
    /// 100 MB limit): it is downloaded on first use like every other voice.
    public static let defaultVoiceId = "de_DE-thorsten-medium"

    public static let all: [PiperVoice] = [
        PiperVoice(
            id: "de_DE-eva_k-x_low", name: "Eva K.", quality: .xLow, sampleRate: 16000,
            model: .init(path: "de/de_DE/eva_k/x_low/de_DE-eva_k-x_low.onnx", size: 20628813, sha256: "e88cf290fbfb768bf111330d2e8a46e376b0d85e3423a28bfebbc863a260dad8"),
            config: .init(path: "de/de_DE/eva_k/x_low/de_DE-eva_k-x_low.onnx.json", size: 4158, sha256: "ef14b3dcb279ab4b18422a7a132877bee7a148821bd91152fb7ae9c4b3d79625"),
            license: .mailabs
        ),
        PiperVoice(
            id: "de_DE-karlsson-low", name: "Karlsson", quality: .low, sampleRate: 16000,
            model: .init(path: "de/de_DE/karlsson/low/de_DE-karlsson-low.onnx", size: 63104526, sha256: "f9793bf7e461a472b3916cf260774bfc9812e9eb72601b147ed649d01064e8fe"),
            config: .init(path: "de/de_DE/karlsson/low/de_DE-karlsson-low.onnx.json", size: 4159, sha256: "3b2095adbfeede316f22007a0a09d4bfc25514b7189850740b06800a6cfb9838"),
            license: .mailabs
        ),
        PiperVoice(
            id: "de_DE-kerstin-low", name: "Kerstin", quality: .low, sampleRate: 16000,
            model: .init(path: "de/de_DE/kerstin/low/de_DE-kerstin-low.onnx", size: 63104526, sha256: "d352a7641892cebf2903859af94e9ba81a141110215fe3943bcda7f7da401b7a"),
            config: .init(path: "de/de_DE/kerstin/low/de_DE-kerstin-low.onnx.json", size: 4158, sha256: "56e708556b7b9b7a53c4f8957e021421e69f11a600962bba554cffbe72cf2d47"),
            license: .kerstinCC0
        ),
        PiperVoice(
            id: "de_DE-pavoque-low", name: "Pavoque", quality: .low, sampleRate: 16000,
            model: .init(path: "de/de_DE/pavoque/low/de_DE-pavoque-low.onnx", size: 63104526, sha256: "96cd41fe2303dfe4745422a2580658bdbc5f935b7ee67640a94da7435a502a26"),
            config: .init(path: "de/de_DE/pavoque/low/de_DE-pavoque-low.onnx.json", size: 4158, sha256: "07d43d8946e869209a12d9b4fd780e3f277fe9afb305c21491a68bd97e01b74f"),
            license: .pavoqueNC
        ),
        PiperVoice(
            id: "de_DE-ramona-low", name: "Ramona", quality: .low, sampleRate: 16000,
            model: .init(path: "de/de_DE/ramona/low/de_DE-ramona-low.onnx", size: 63104526, sha256: "a1068592532aad8c49bf3d1a01b8749c11d7dba726689ee28ad64e7b627ae4c5"),
            config: .init(path: "de/de_DE/ramona/low/de_DE-ramona-low.onnx.json", size: 4157, sha256: "64906ab7a050ac685fa3dcea044baa798f67ed77be164f9c668a69298c6487d2"),
            license: .mailabs
        ),
        PiperVoice(
            id: "de_DE-thorsten-low", name: "Thorsten", quality: .low, sampleRate: 16000,
            model: .init(path: "de/de_DE/thorsten/low/de_DE-thorsten-low.onnx", size: 63104526, sha256: "9ac27fad17cec5c1a791161976a64f026f16fc058b400b1fea62565b8b2cf375"),
            config: .init(path: "de/de_DE/thorsten/low/de_DE-thorsten-low.onnx.json", size: 4159, sha256: "df38e892ed949f62d0c40978bc666de0b341c5f7921840ae7c72f4df8e8ffa05"),
            license: .thorstenCC0
        ),
        PiperVoice(
            id: "de_DE-thorsten-medium", name: "Thorsten", quality: .medium, sampleRate: 22050,
            model: .init(path: "de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx", size: 63201294, sha256: "7e64762d8e5118bb578f2eea6207e1a35a8e0c30595010b666f983fc87bb7819"),
            config: .init(path: "de/de_DE/thorsten/medium/de_DE-thorsten-medium.onnx.json", size: 4819, sha256: "974adee790533adb273a1ac88f49027d2a1b8f0f2cf4905954a4791e79264e85"),
            license: .thorstenCC0
        ),
        PiperVoice(
            id: "de_DE-thorsten-high", name: "Thorsten", quality: .high, sampleRate: 22050,
            model: .init(path: "de/de_DE/thorsten/high/de_DE-thorsten-high.onnx", size: 113895201, sha256: "9df1c43c61149ef9b39e618e2b861fbe41e1fcea9390b2dac62e8761573ea4f1"),
            config: .init(path: "de/de_DE/thorsten/high/de_DE-thorsten-high.onnx.json", size: 4875, sha256: "6de734444e4c3f9e33b7ebe2746dbc19b71e85f613e79c65acf623200b99a76a"),
            license: .thorstenCC0
        ),
        PiperVoice(
            id: "de_DE-thorsten_emotional-medium", name: "Thorsten emotional", quality: .medium, sampleRate: 22050,
            model: .init(path: "de/de_DE/thorsten_emotional/medium/de_DE-thorsten_emotional-medium.onnx", size: 76745905, sha256: "c1764e652266cd6dcebf1b95c61973df5970a5f5272e94b655ff1ddf9a99d1ff"),
            config: .init(path: "de/de_DE/thorsten_emotional/medium/de_DE-thorsten_emotional-medium.onnx.json", size: 5031, sha256: "92895b9e99f7cfc13f4a9879da615c3d6e0baa4d660e26d7b685abdd27a6d1d3"),
            license: .thorstenCC0, speakerNames: ["amüsiert", "wütend", "angewidert", "betrunken", "neutral", "schläfrig", "überrascht", "flüsternd"], defaultSpeaker: 4
        ),
    ]

    /// What the voice field lists: redistribution allowed (PAVOQUE is CC BY-NC-SA → left out).
    public static var offered: [PiperVoice] { all.filter(\.license.allowsRedistribution) }
    public static var excluded: [PiperVoice] { all.filter { !$0.license.allowsRedistribution } }

    public static var defaultVoice: PiperVoice { voice(id: defaultVoiceId)! }

    /// Only offered voices – an excluded or unknown id is nil.
    public static func voice(id: String) -> PiperVoice? {
        offered.first { $0.id == id }
    }
}
