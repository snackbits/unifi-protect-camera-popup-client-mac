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
    /// Line crossings (Protect event `smartDetectLine`), separate from detections in a zone.
    /// Protect does not say which line was crossed, only what crossed it.
    case personLine
    case vehicleLine
    case animalLine

    /// Display order in the UI.
    public static let ordered: [TriggerKind] = [
        .ring, .person, .package, .animal, .vehicle, .licensePlate, .face, .motion,
        .speak, .bark, .babyCry, .glassBreak, .smoke, .carbonMonoxide, .siren, .carHorn, .burglar,
        .personLine, .vehicleLine, .animalLine,
    ]

    /// Chip order in settings and onboarding (template): specific detections first, motion last,
    /// then the line crossings (their own chip row).
    public static let displayOrder: [TriggerKind] = [
        .ring, .person, .package, .animal, .vehicle, .licensePlate, .face,
        .speak, .bark, .babyCry, .glassBreak, .smoke, .carbonMonoxide, .siren, .carHorn, .burglar,
        .motion,
        .personLine, .vehicleLine, .animalLine,
    ]

    /// The line-crossing kinds, in chip order.
    public static let lineKinds: [TriggerKind] = [.personLine, .vehicleLine, .animalLine]

    public var isLine: Bool { Self.lineKinds.contains(self) }

    /// The line-crossing kind for an object kind (person → personLine); nil for everything that
    /// cannot cross a line.
    public var lineVariant: TriggerKind? {
        switch self {
        case .person: return .personLine
        case .vehicle: return .vehicleLine
        case .animal: return .animalLine
        default: return nil
        }
    }

    /// The object kind of a line crossing (personLine → person); the kind itself otherwise.
    public var base: TriggerKind {
        switch self {
        case .personLine: return .person
        case .vehicleLine: return .vehicle
        case .animalLine: return .animal
        default: return self
        }
    }

    /// Chips for one camera: only what is switched on in Protect (`enabled`), in display order –
    /// zone/sound/motion kinds in `detections`, line crossings in `lines`. The order depends only
    /// on the camera, so chips never jump when toggled.
    public static func chips(enabled: Set<TriggerKind>) -> (detections: [TriggerKind], lines: [TriggerKind]) {
        let shown = displayOrder.filter(enabled.contains)
        return (shown.filter { !$0.isLine }, shown.filter(\.isLine))
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
        case .personLine: return "Person überquert Linie"
        case .vehicleLine: return "Fahrzeug überquert Linie"
        case .animalLine: return "Tier überquert Linie"
        }
    }

    /// Chip text: line crossings sit in their own row („Linie überquert“), so only the object.
    public var chipLabel: String { isLine ? base.label : label }
}
