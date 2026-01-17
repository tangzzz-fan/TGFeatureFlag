import Foundation

/// Protocol defining the unique identifier and default behavior for a Feature Flag.
///
/// Implement this protocol (usually on an Enum) to define the available flags in your application.
///
/// Example:
/// ```swift
/// enum AppFeature: String, FeatureFlagKey {
///     case newProfile
///     case apiBaseUrl
///
///     var defaultValue: Any {
///         switch self {
///         case .newProfile: return true
///         case .apiBaseUrl: return "https://api.example.com"
///         }
///     }
/// }
/// ```
public protocol FeatureFlagKey: RawRepresentable, Sendable, Hashable where RawValue == String {
    /// The type of value this flag holds (Bool, String, Int, Double).
    /// Swift protocols don't support generic associated types in a simple way for heterogeneous collections,
    /// so we use `Any` for the default value and cast at runtime.
    /// However, for type safety, we can encourage usage of specific accessors.
    
    /// The default value of the flag if no provider returns a specific value.
    var defaultValue: Any { get }
    
    /// A human-readable description for debug tools (Optional).
    var description: String { get }
}

public extension FeatureFlagKey {
    var description: String { rawValue }
}
