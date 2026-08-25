import Foundation

/// A cold, Sendable snapshot of resolved feature-flag values.
///
/// Intended for Redux-style apps: resolve once (via `FeatureFlagResolver`), dispatch the
/// snapshot into the Store, and treat the Store as the source of truth. This type is a
/// **generic** key → value map; app domains map it into business-shaped DTOs.
public struct FeatureFlagSnapshot: Sendable, Equatable, Codable, Hashable {
    /// Resolved values keyed by lookup key (`FeatureFlagKey.lookupKey`).
    public var values: [String: FeatureFlagValue]

    public init(values: [String: FeatureFlagValue] = [:]) {
        self.values = values
    }

    public subscript(key: String) -> FeatureFlagValue? {
        get { values[key] }
        set { values[key] = newValue }
    }

    /// Returns the resolved value for a typed feature key, if present in the snapshot.
    public func value<F: FeatureFlagKey>(for feature: F) -> FeatureFlagValue? {
        values[feature.lookupKey]
    }

    /// Returns a boolean for `feature`, falling back to `feature.defaultValue` when missing
    /// or non-boolean.
    public func isEnabled<F: FeatureFlagKey>(_ feature: F) -> Bool {
        if let value = values[feature.lookupKey], let bool = value.boolValue {
            return bool
        }
        return feature.defaultValue.boolValue ?? false
    }

    public func bool(for key: String) -> Bool? {
        values[key]?.boolValue
    }

    public func string(for key: String) -> String? {
        values[key]?.stringValue
    }

    public func int(for key: String) -> Int? {
        values[key]?.intValue
    }

    public func double(for key: String) -> Double? {
        values[key]?.doubleValue
    }
}
