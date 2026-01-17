import Foundation

/// Protocol defining a source for Feature Flag values.
///
/// Providers can be chained in the `FeatureFlagService`. Common examples include:
/// - `DebugProvider`: Overrides from a developer menu.
/// - `RemoteConfigProvider`: Values fetched from a backend.
/// - `LocalProvider`: Default values hardcoded or from a local file.
public protocol FeatureFlagProvider: Sendable {
    /// The unique name of the provider (e.g., "RemoteConfig", "Debug").
    var name: String { get }
    
    /// Retrieves the value for a specific feature flag.
    /// - Parameter key: The feature flag key string.
    /// - Returns: The value if found, otherwise `nil`.
    func value(for key: String) -> Any?
}
