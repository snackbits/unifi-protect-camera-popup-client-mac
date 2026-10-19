import Foundation

/// What can make a camera open a popup. Raw values are stored in settings.json.
public enum TriggerKind: String, Codable, CaseIterable, Sendable {
    case ring
    case person
    case package
    case animal
    case vehicle
    case licensePlate
    case face
    case motion
    case speak
    case bark
    case babyCry
    case glassBreak
    case smoke
    case carbonMonoxide
    case siren
    case carHorn
    case burglar

    /// Display order in the UI.
    public static let ordered: [TriggerKind] = [
        .ring, .person, .package, .animal, .vehicle, .licensePlate, .face, .motion,
        .speak, .bark, .babyCry, .glassBreak, .smoke, .carbonMonoxide, .siren, .carHorn, .burglar
    ]

    /// Chip order in settings and onboarding (template): specific detections first, motion last.
    public static let displayOrder: [TriggerKind] = [
        .ring, .person, .package, .animal, .vehicle, .licensePlate, .face,
        .speak, .bark, .babyCry, .glassBreak, .smoke, .carbonMonoxide, .siren, .carHorn, .burglar,
        .motion,
    ]

    /// Offered even when a camera cannot detect them (shown struck through).
    public static let alwaysShown: Set<TriggerKind> = [.ring, .person, .package, .animal, .vehicle]

    /// Chips for one camera: supported kinds in display order, then the unsupported core kinds.
    /// The order depends only on the camera, so chips never jump when toggled.
    public static func chips(supported: Set<TriggerKind>) -> [TriggerChipItem] {
        let shown = displayOrder.filter { supported.contains($0) || alwaysShown.contains($0) }
        return shown.filter { supported.contains($0) }.map { TriggerChipItem(kind: $0, isSupported: true) }
            + shown.filter { !supported.contains($0) }.map { TriggerChipItem(kind: $0, isSupported: false) }
    }

    /// Maps Protect `smartDetectTypes` / audio type wire values.
    public init?(wireValue: String) {
        switch wireValue {
        case "person": self = .person
        case "vehicle", "car": self = .vehicle
        case "animal", "pet": self = .animal
        case "package": self = .package
        case "licensePlate": self = .licensePlate
        case "face": self = .face
        case "alrmSpeak": self = .speak
        case "alrmBark": self = .bark
        case "alrmBabyCry": self = .babyCry
        case "alrmGlassBreak": self = .glassBreak
        case "alrmSmoke", "smoke_cmonx": self = .smoke
        case "alrmCmonx": self = .carbonMonoxide
        case "alrmSiren": self = .siren
        case "alrmCarHorn": self = .carHorn
        case "alrmBurglar": self = .burglar
        default: return nil
        }
    }

    public var label: String {
        switch self {
        case .ring: return "Klingel"
        case .person: return "Person"
        case .package: return "Paket"
        case .animal: return "Tier"
        case .vehicle: return "Fahrzeug"
        case .licensePlate: return "Kennzeichen"
        case .face: return "Gesicht"
        case .motion: return "Bewegung"
        case .speak: return "Sprache"
        case .bark: return "Hundebellen"
        case .babyCry: return "Babyweinen"
        case .glassBreak: return "Glasbruch"
        case .smoke: return "Rauchmelder"
        case .carbonMonoxide: return "CO-Melder"
        case .siren: return "Sirene"
        case .carHorn: return "Hupe"
        case .burglar: return "Einbruchalarm"
        }
    }
}

public struct TriggerChipItem: Equatable, Sendable {
    public let kind: TriggerKind
    public let isSupported: Bool
}
