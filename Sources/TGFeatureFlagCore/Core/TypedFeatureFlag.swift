import Foundation

/// A Swift type that a feature flag can hold.
///
/// The set is deliberately closed to the four cases `FeatureFlagValue` supports: an open
/// protocol would let a conformer invent a value shape the snapshot wire format cannot encode.
public protocol FeatureFlagValueConvertible: Sendable, Equatable {
    /// Wraps the value for storage in a snapshot or provider.
    var featureFlagValue: FeatureFlagValue { get }

    /// Unwraps a stored value, or `nil` when the stored case does not match.
    init?(featureFlagValue: FeatureFlagValue)
}

extension Bool: FeatureFlagValueConvertible {
    public var featureFlagValue: FeatureFlagValue { .bool(self) }

    public init?(featureFlagValue: FeatureFlagValue) {
        guard case .bool(let value) = featureFlagValue else { return nil }
        self = value
    }
}

extension String: FeatureFlagValueConvertible {
    public var featureFlagValue: FeatureFlagValue { .string(self) }

    public init?(featureFlagValue: FeatureFlagValue) {
        guard case .string(let value) = featureFlagValue else { return nil }
        self = value
    }
}

extension Int: FeatureFlagValueConvertible {
    public var featureFlagValue: FeatureFlagValue { .int(self) }

    public init?(featureFlagValue: FeatureFlagValue) {
        guard case .int(let value) = featureFlagValue else { return nil }
        self = value
    }
}

extension Double: FeatureFlagValueConvertible {
    public var featureFlagValue: FeatureFlagValue { .double(self) }

    public init?(featureFlagValue: FeatureFlagValue) {
        guard case .double(let value) = featureFlagValue else { return nil }
        self = value
    }
}

/// A feature flag whose value type is known to the compiler.
///
/// Adopting this makes a whole class of mistakes impossible at the call site: reading a boolean
/// flag yields a `Bool` rather than a `FeatureFlagValue` that callers must unwrap, and
/// `isEnabled` only accepts keys whose value type is `Bool`.
///
/// The cost is one value type per enum, because `Value` is an associated type. Mixed flags have
/// to live in separate enums — which is usually an improvement anyway, since a boolean switch
/// and a string configuration value have nothing in common beyond both being "flags".
///
/// ```swift
/// enum AppFeature: String, TypedFeatureFlag {
///     case newProfileDesign = "feature_new_profile"
///
///     var typedDefaultValue: Bool { false }
/// }
///
/// let enabled: Bool = resolver.isEnabled(AppFeature.newProfileDesign)
/// ```
public protocol TypedFeatureFlag: FeatureFlagKey {
    /// The Swift type this flag resolves to.
    associatedtype Value: FeatureFlagValueConvertible

    /// The value used when no provider supplies one.
    var typedDefaultValue: Value { get }
}

public extension TypedFeatureFlag {
    /// Derived from `typedDefaultValue`, so the two can never disagree.
    var defaultValue: FeatureFlagValue { typedDefaultValue.featureFlagValue }
}
