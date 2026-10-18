import Foundation

/// One offered mute length ("Kurz" / "Lang" in Einstellungen › Allgemein).
public struct MuteDuration: Codable, Hashable, Sendable {
    public enum Unit: String, Codable, CaseIterable, Sendable {
        case minutes
        case hours

        /// Unit label of the settings field. Always plural, as in the template ("1" + "Stunden").
        public var label: String {
            switch self {
            case .minutes: return "Minuten"
            case .hours: return "Stunden"
            }
        }
    }

    public static let allowedValues = 1...999
    public static let defaultShort = MuteDuration(value: 15, unit: .minutes)
    public static let defaultLong = MuteDuration(value: 1, unit: .hours)

    public private(set) var value: Int
    public var unit: Unit

    public init(value: Int, unit: Unit) {
        self.value = Self.clamped(value)
        self.unit = unit
    }

    private enum CodingKeys: String, CodingKey { case value, unit }

    /// Lenient: a broken or out-of-range value never fails the whole settings file.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let value = (try? container.decode(Int.self, forKey: .value)) ?? 15
        let unit = (try? container.decode(Unit.self, forKey: .unit)) ?? .minutes
        self.init(value: value, unit: unit)
    }

    public var seconds: TimeInterval {
        TimeInterval(value) * (unit == .minutes ? 60 : 3600)
    }

    /// Menu buttons: "15 Min.", "1 Std."
    public var shortLabel: String {
        "\(value) \(unit == .minutes ? "Min." : "Std.")"
    }

    /// Popup mute menu: "15 Minuten", "1 Minute", "1 Stunde", "2 Stunden".
    public var longLabel: String {
        switch unit {
        case .minutes: return value == 1 ? "1 Minute" : "\(value) Minuten"
        case .hours: return value == 1 ? "1 Stunde" : "\(value) Stunden"
        }
    }

    public func withValue(_ newValue: Int) -> MuteDuration {
        MuteDuration(value: newValue, unit: unit)
    }

    /// Text field input → value within `allowedValues`. nil for empty or non-numeric input;
    /// the field then keeps its previous value.
    public static func parseValue(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return clamped(Int(trimmed) ?? allowedValues.upperBound)
    }

    static func clamped(_ value: Int) -> Int {
        min(max(value, allowedValues.lowerBound), allowedValues.upperBound)
    }
}
