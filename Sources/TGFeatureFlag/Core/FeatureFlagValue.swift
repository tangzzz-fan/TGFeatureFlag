import Foundation

/// A typed feature-flag value.
///
/// Replaces untyped `Any` storage so flag values are `Sendable`, `Equatable`, and `Codable`
/// and safe to put in Redux snapshots or cross actor boundaries.
public enum FeatureFlagValue: Sendable, Equatable, Codable, Hashable {
    case bool(Bool)
    case string(String)
    case int(Int)
    case double(Double)

    /// The boolean payload, if this value is `.bool`.
    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    /// The string payload, if this value is `.string`.
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The integer payload, if this value is `.int`.
    public var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }

    /// The double payload, if this value is `.double`.
    public var doubleValue: Double? {
        if case .double(let value) = self { return value }
        return nil
    }

    /// Creates a value from a `UserDefaults` / Objective-C bridge object when possible.
    public init?(any value: Any) {
        switch value {
        case let string as String:
            self = .string(string)
        case let number as NSNumber:
            // UserDefaults stores Bool/Int/Double as NSNumber — inspect objCType.
            let objCType = String(cString: number.objCType)
            if objCType == "c" || objCType == "B" {
                self = .bool(number.boolValue)
            } else if objCType == "d" || objCType == "f" {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        case let bool as Bool:
            self = .bool(bool)
        case let int as Int:
            self = .int(int)
        case let double as Double:
            self = .double(double)
        default:
            return nil
        }
    }
}

extension FeatureFlagValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .bool(let value): return String(describing: value)
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        }
    }
}
